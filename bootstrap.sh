#!/bin/bash
# EC2 user-data that prepares an instance to run ESPHome cloud builds.
# Launch instances with ./launch.sh, which fills in KONNECTED_ENV for the environment.
# Progress/errors are logged to /var/log/cloud-init-output.log on the instance.
set -euxo pipefail

KONNECTED_ENV="__KONNECTED_ENV__"
# ESPHome raises its minimum Python over time; bump this (and relaunch) when it does
PYTHON=python3.12

if [[ "${KONNECTED_ENV}" == __* ]]; then
  echo "KONNECTED_ENV was not set; launch with ./launch.sh <env>" >&2
  exit 1
fi

dnf install -y ${PYTHON} ${PYTHON}-pip git

# small instances (t4g.micro) need swap headroom for ESP-IDF builds
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 2000000 ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi

cd /home/ec2-user

cat > .env <<EOF
KONNECTED_ENV=${KONNECTED_ENV}
PYTHON=${PYTHON}
EOF

# run by the Update_ESPHome maintenance window
cat > update-esphome.sh <<'EOF'
#!/bin/bash
# Upgrades ESPHome, then fails if the installed version is still behind PyPI
# (e.g. the latest release requires a newer Python than this instance has).
set -o allexport
source ~/.env
set +o allexport

${PYTHON} -m pip install --user --upgrade --no-input esphome || exit 1

installed=$(${PYTHON} -m pip show esphome | awk '/^Version:/ {print $2}')
latest=$(curl -fsS https://pypi.org/pypi/esphome/json | ${PYTHON} -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])')
echo "ESPHome installed: ${installed}, latest on PyPI: ${latest}"

if [ "${installed}" != "${latest}" ]
then
  echo "ERROR: ESPHome ${latest} was not installed. Check its requires_python against $(${PYTHON} --version)." >&2
  exit 1
fi
EOF

chown ec2-user:ec2-user .env update-esphome.sh
chmod +x update-esphome.sh

runuser -l ec2-user -c "${PYTHON} -m pip install --user --no-input esphome"
runuser -l ec2-user -c 'mkdir -p esphome-configs'
runuser -l ec2-user -c 'wget https://raw.githubusercontent.com/konnected-io/esphome-ec2-build/main/build.sh'
runuser -l ec2-user -c 'chmod +x build.sh'
