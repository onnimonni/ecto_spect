{ pkgs, lib, config, inputs, ... }:

{
  packages = [ pkgs.git ];

  languages.elixir.enable = true;

  services.postgres = {
    enable = true;
    initialDatabases = [{ name = "ecto_verify_test"; }];
  };
}
