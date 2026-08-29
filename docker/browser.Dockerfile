# Headless browser for checking the LED matrix simulator page (sim/).
#
# Deliberately a separate image from the firmware one: it exists only to run a
# browser, and nothing in the firmware build needs Node or Chromium. Build it
# when you need it and drop it when you do not.
FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /opt/browser-check

# Browsers go to a fixed path rather than the installing user's cache: the
# image installs them as root, but the container runs as the host user with
# HOME=/tmp, and Playwright would look under that HOME instead.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# `playwright install --with-deps` pulls the shared libraries Chromium needs on
# a slim image, which is the part that is tedious to get right by hand.
RUN npm init -y > /dev/null \
    && npm install --no-fund --no-audit playwright \
    && npx playwright install --with-deps chromium \
    && npm cache clean --force

# The checker is bind-mounted from the repository, so it has to find the
# library that lives in the image.
ENV NODE_PATH=/opt/browser-check/node_modules

# Chromium writes its profile here; the container runs as the host user, who
# has no home directory inside the image.
ENV HOME=/tmp

WORKDIR /work
CMD ["node", "/work/tools/browser-check/check.cjs"]
