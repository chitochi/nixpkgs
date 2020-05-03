{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.caddy;
  configFile = pkgs.writeText "Caddyfile" cfg.config;

  # v2-specific options
  isCaddy2 = versionAtLeast cfg.package.version "2.0";
  tlsConfig = {
    apps.tls.automation.policies = [{
      issuer = {
        inherit (cfg) ca email;
        module = "acme";
      };
    }];
  };
  adaptedConfig = importJSON (pkgs.runCommand "caddy-config-adapted.json" { } ''
    ${cfg.package}/bin/caddy adapt \
      --config ${configFile} --adapter ${cfg.adapter} > $out
  '');
  configJSON = pkgs.writeText "caddy-config.json" (builtins.toJSON
    (recursiveUpdate adaptedConfig tlsConfig));
in {
  options.services.caddy = {
    enable = mkEnableOption "Caddy web server";

    config = mkOption {
      default = "";
      # TODO: update example text on v2.0 release
      example = ''
        example.com {
        gzip
        minify
        log syslog

        root /srv/http
        }
      '';
      type = types.lines;
      description = "Verbatim Caddyfile to use";
    };

    adapter = mkOption {
      default = "caddyfile";
      example = "nginx";
      type = types.str;
      description = ''
        Name of the config adapter to use.

        See https://caddyserver.com/docs/config-adapters for the full list.
      '';
    };

    ca = mkOption {
      default = "https://acme-v02.api.letsencrypt.org/directory";
      example = "https://acme-staging-v02.api.letsencrypt.org/directory";
      type = types.str;
      description = "Certificate authority ACME server. The default (Let's Encrypt production server) should be fine for most people.";
    };

    email = mkOption {
      default = "";
      type = types.str;
      description = "Email address (for Let's Encrypt certificate)";
    };

    agree = mkOption {
      default = false;
      type = types.bool;
      description = "Agree to Let's Encrypt Subscriber Agreement";
    };

    dataDir = mkOption {
      default = "/var/lib/caddy";
      type = types.path;
      description = ''
        The data directory, for storing certificates. Before 17.09, this
        would create a .caddy directory. With 17.09 the contents of the
        .caddy directory are in the specified data directory instead.
      '';
    };

    package = mkOption {
      default = pkgs.caddy;
      defaultText = "pkgs.caddy";
      example = "pkgs.caddy2";
      type = types.package;
      description = ''
        Caddy package to use.

        Note: to use Caddy v2, set this to <option>pkgs.caddy2</option>.
        v2 will become the default after it is released.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.caddy = {
      description = "Caddy web server";
      # upstream unit: https://github.com/caddyserver/caddy/blob/master/dist/init/linux-systemd/caddy.service
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ]; # systemd-networkd-wait-online.service
      wantedBy = [ "multi-user.target" ];
      environment = mkIf (versionAtLeast config.system.stateVersion "17.09" && !isCaddy2)
        { CADDYPATH = cfg.dataDir; };
      serviceConfig = {
        ExecStart = if isCaddy2 then ''
          ${cfg.package}/bin/caddy run --config ${configJSON}
        '' else ''
          ${cfg.package}/bin/caddy -log stdout -log-timestamps=false \
            -root=/var/tmp -conf=${configFile} \
            -ca=${cfg.ca} -email=${cfg.email} ${optionalString cfg.agree "-agree"}
        '';
        ExecReload = "${pkgs.coreutils}/bin/kill -USR1 $MAINPID";
        Type = "simple";
        User = "caddy";
        Group = "caddy";
        Restart = "on-abnormal";
        StartLimitIntervalSec = 14400;
        StartLimitBurst = 10;
        AmbientCapabilities = "cap_net_bind_service";
        CapabilityBoundingSet = "cap_net_bind_service";
        NoNewPrivileges = true;
        LimitNPROC = 512;
        LimitNOFILE = 1048576;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectSystem = "full";
        ReadWriteDirectories = cfg.dataDir;
        KillMode = "mixed";
        KillSignal = "SIGQUIT";
        TimeoutStopSec = "5s";
      };
    };

    users.users.caddy = {
      group = "caddy";
      uid = config.ids.uids.caddy;
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.caddy.gid = config.ids.uids.caddy;
  };
}
