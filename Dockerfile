FROM balena/armv7hf-supervisor:v9.0.1
RUN mkdir /tmp/d1 && touch /tmp/d1/d1f1 && touch /tmp/f1 && touch /tmp/f2
RUN rm -R /tmp/d1 && mkdir /tmp/d1 && touch /tmp/d1/d1f2 && rm /tmp/f1
