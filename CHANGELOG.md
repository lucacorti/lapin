2.0.0 (2021-11-09)

This is a major release. Lapin itself is API compatible with 1.0, however, due to changes in the
underlying rabbitmq libraries and the elixir `amqp` library there are runtime breaking changes.

This release requires Elixir 1.15+ and OTP 26+. Please note that rabbitmq does not recommend
running on OTP 27 yet.

Check `amqp` release notes for more details: https://github.com/pma/amqp/wiki/4.0-Release-Notes

- Require Elixir 1.15+ and OTP 26+
- Update CI
- Rewrite the internals on `Lapin.Connection` to use `:gen_statem` and remove `Connection` dependency
