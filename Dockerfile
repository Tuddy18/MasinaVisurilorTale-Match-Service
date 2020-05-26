FROM bitwalker/alpine-elixir:1.10.2 as build

COPY . .

RUN export MIX_ENV=prod 
RUN rm -Rf _build
RUN mix do deps.get, deps.compile, compile
#RUN mix do deps.get, deps.compile, compile

EXPOSE 4003

ENTRYPOINT ["mix", "run", "--no-halt"]