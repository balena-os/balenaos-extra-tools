#!/bin/bash

set -e

ENGINE="balena"
DOCKERDIR="/mnt/data/docker/"
OVERLAYDIR="$DOCKERDIR/overlay2"
AUFSDIR="$DOCKERDIR/aufs"

# https://github.com/balena-os/balena-engine/blob/15e30e91a3426488c01823ca2a446b71e81ea263/daemon/graphdriver/overlay2/randomid.go#L19
generateID () {
	local _len=26 # https://github.com/balena-os/balena-engine/blob/15e30e91a3426488c01823ca2a446b71e81ea263/daemon/graphdriver/overlay2/overlay.go#L85
	tr -dc 'A-Z0-9'  < /dev/urandom | fold -w "$_len" | head -n1
}

log () {
	if [ "$1" = "ERROR" ]; then
		echo "$2"
		exit 1
	fi
	echo "$1"
}

clean_containers () {
	# Make sure no new containers come up or are running
	log "Stopping systemd services ..."
	systemctl stop update-resin-supervisor.timer
	systemctl stop update-resin-supervisor
	systemctl stop resin-supervisor
	systemctl start balena
	if [ -n "$("$ENGINE" ps -a -q)" ]; then
		log "Found containers stopping ..."
		"$ENGINE" stop "$("$ENGINE" ps -a -q)" &> /dev/null
		log "Found containers removing ..."
		"$ENGINE" rm "$("$ENGINE" ps -a -q)" &> /dev/null
		log "Done."
	fi
	systemctl stop balena
}

if [ ! -d "$DOCKERDIR/aufs" ]; then
	log ERROR "No aufs set in $DOCKERDIR ?."
fi
if [ -d "$DOCKERDIR/overlay2" ]; then
	log ERROR "overlayfs2 already set in $DOCKERDIR ?."
fi

log "Using $DOCKERDIR as $ENGINE root directory."

# TODO: handle containers as well
clean_containers

mkdir -p "$DOCKERDIR/overlay2/l"
log "Migrating layers ..."
for aufs_layerpath in "$DOCKERDIR"/aufs/diff/*; do
	layer="$(basename "$aufs_layerpath")"
	log "---> $layer ..."

	# root layer directrory
	mkdir -p "$OVERLAYDIR/$layer"

	# link
	if [ ! -f "$OVERLAYDIR/$layer/link" ]; then
		printf "%s" "$(generateID)" > "$OVERLAYDIR/$layer/link"
		ln -s "../$layer/diff" "$OVERLAYDIR/l/$(cat "$OVERLAYDIR/$layer/link")"
	fi

	# lower
	lower=""
	while IFS= read -r parent_layer; do
		if [ ! -f "$OVERLAYDIR/$parent_layer/link" ]; then
			mkdir -p "$OVERLAYDIR/$parent_layer"
			printf "%s" "$(generateID)" > "$OVERLAYDIR/$parent_layer/link"
			ln -s "../$parent_layer/diff" "$OVERLAYDIR/l/$(cat "$OVERLAYDIR/$parent_layer/link")"
		fi
		parent_layer_id="$(cat "$OVERLAYDIR/$parent_layer/link")"
		if [ -z "$lower" ]; then
			lower="l/$parent_layer_id"
		else
			lower="${lower}:l/$parent_layer_id"
		fi
	done < "$AUFSDIR/layers/$layer"
	if [ -n "$lower" ]; then
		echo -n "$lower" > "$OVERLAYDIR/$layer/lower"
		
		# work
		mkdir -p "$OVERLAYDIR/$layer/work"
	fi


	# diff
	mkdir -p "$OVERLAYDIR/$layer"
	mv "$aufs_layerpath" "$OVERLAYDIR/$layer/diff"
done

# image
mv "$DOCKERDIR/image/aufs" "$DOCKERDIR/image/overlay2"

# Clean
rm -rf "$AUFSDIR"

log "Switching balena engine to overlay2 ... "
mount -o remount,rw /
sed -i "s/aufs/overlay2/g" /lib/systemd/system/balena.service
if [ -f "/etc/systemd/system/balena.service.d/balena.conf" ]; then
	sed -i "s/aufs/overlay2/g" /etc/systemd/system/balena.service.d/balena.conf
fi
systemctl daemon-reload
mount -o remount,ro /

sync

log "Bringing back systemd services ..."
systemctl start balena
systemctl start resin-supervisor
systemctl start update-resin-supervisor.timer

log "Done!"
