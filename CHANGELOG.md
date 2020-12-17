## 0.2.3

* Upgrade Elixir and dependencies versions

## 0.2.1

* Allow Fettle ~> 1.0 or ~> 0.1
* Fix @impl warning under Elixir 1.6

## 0.2.0

* option for configuring `HTTPoison`, should, of course be `httpoison` not `poison`.
* set default configuration for `HTTPoison` pool timeout to a more reasonable 10s (default it 150s!)
* make it easier to override HTTPoison/Hackney defaults by adding `default_httpoison_opts/1` and `default_hackney_opts/1`.

## 0.1.1

* attempt to fix race-condition between first test run and hackney manager being available (very possible when `init_delay_ms` is zero).

## 0.1.0

* Initial release.
