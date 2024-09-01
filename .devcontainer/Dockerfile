FROM debian:bookworm-slim

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd --gid $USER_GID $USERNAME \
  && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
  && apt-get update \
  && apt-get install -y \
  tzdata \
  sudo \
  && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
  && chmod 0440 /etc/sudoers.d/$USERNAME

ENV TZ=Asia/Tokyo

RUN apt-get update \
  && apt-get install -y \
  curl \
  git \
  less \
  sudo \
  unzip \
  zsh \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

ENV SHELL /usr/bin/zsh

RUN curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh \
  && curl -fsSL https://dprint.dev/install.sh | zsh \
  && curl -fsSL https://bun.sh/install | bash

ENV PATH="/root/.bun/bin:${PATH}"

USER ${USERNAME}

CMD ["/bin/zsh"]
