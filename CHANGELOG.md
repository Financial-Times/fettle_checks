## 0.2.0

* option for configuring `HTTPoison`, should, of course be `httppoison` not `poison`.
* set default configuration for `HTTPoison` pool timeout to a more reasonable 10s (default it 150s!)
* make it easier to override HTTPoison/Hackney defaults by adding `default_httpoison_opts/1` and `default_hackney_opts/1`.

## 0.1.1

* attempt to fix race-condition between first test run and hackney manager being available (very possible when `init_delay_ms` is zero).

## 0.1.0

* Initial release.
