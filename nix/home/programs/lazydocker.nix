{config, ...}: let
  flavor = config.catppuccin.flavor;
  p = config.catppuccinLib.palettes.${flavor};
  accent = p.${config.catppuccin.accent};
in {
  programs.lazydocker = {
    enable = true;
    settings = {
      gui = {
        scrollHeight = 2;
        language = "auto";
        sidePanelWidth = 0.333;
        expandFocusedSidePanel = false;
        screenMode = "normal";
        returnImmediately = false;
        wrapMainPanel = true;
        theme = {
          activeBorderColor = [accent.hex "bold"];
          inactiveBorderColor = [p.overlay0.hex];
          selectedLineBgColor = [p.surface0.hex];
          optionsTextColor = [accent.hex];
        };
      };

      logs = {
        timestamps = true;
        since = "60m";
        tail = "300";
      };

      commandTemplates = {
        dockerCompose = "docker compose";
        restartPolicy = "unless-stopped";
      };

      customCommands.containers = [
        {
          name = "shell (bash)";
          attach = true;
          command = "docker exec -it {{ .Container.ID }} bash";
          serviceNames = [];
        }
        {
          name = "shell (sh)";
          attach = true;
          command = "docker exec -it {{ .Container.ID }} sh";
          serviceNames = [];
        }
        {
          name = "view logs (last 100)";
          command = "docker logs --tail 100 {{ .Container.ID }}";
          serviceNames = [];
        }
      ];

      stats.graphs = [
        {
          caption = "CPU (%)";
          statPath = "DerivedStats.CPUPercentage";
          color = "blue";
        }
        {
          caption = "Memory (%)";
          statPath = "DerivedStats.MemoryPercentage";
          color = "green";
        }
      ];
    };
  };
}
