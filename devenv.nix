{ pkgs, lib, config, inputs, ... }:

{
  packages = [ pkgs.git ];

  languages.elixir.enable = true;

  services.postgres = {
    enable = true;
    initialDatabases = [{ name = "ecto_verify_test"; }];
    listen_addresses = "127.0.0.1";
  };
}
