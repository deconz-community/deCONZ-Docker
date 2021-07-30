#!/bin/sh

if [ "$DECONZ_START_VERBOSE" = 1 ]; then
  set -x
fi

echo "[marthoc/deconz] Starting deCONZ..."
echo "[marthoc/deconz] Current deCONZ version: $DECONZ_VERSION"
echo "[marthoc/deconz] Web UI port: $DECONZ_WEB_PORT"
echo "[marthoc/deconz] Websockets port: $DECONZ_WS_PORT"

DECONZ_OPTS="--auto-connect=1 \
        --appdata=/opt/deCONZ/data \
        --dbg-info=$DEBUG_INFO \
        --dbg-aps=$DEBUG_APS \
        --dbg-zcl=$DEBUG_ZCL \
        --dbg-zdp=$DEBUG_ZDP \
        --dbg-otau=$DEBUG_OTAU \
        --http-port=$DECONZ_WEB_PORT \
        --ws-port=$DECONZ_WS_PORT"

echo "[marthoc/deconz] Modifying user and group ID"
if [ "$DECONZ_UID" != 1000 ]; then
  DECONZ_UID=${DECONZ_UID:-1000}
  sudo usermod -o -u "$DECONZ_UID" deconz
fi
if [ "$DECONZ_GID" != 1000 ]; then
  DECONZ_GID=${DECONZ_GID:-1000}
  sudo groupmod -o -g "$DECONZ_GID" deconz
fi

echo "[marthoc/deconz] Checking device group ID"
if [ "$DECONZ_DEVICE" != 0 ]; then
  DEVICE=$DECONZ_DEVICE
else
 if [ -f /dev/ttyUSB0 ]; then
   DEVICE=/dev/ttyUSB0
 fi
 if [ -f /dev/ttyACM0 ]; then
   DEVICE=/dev/ttyACM0
 fi
 if [ -f /dev/ttyAMA0 ]; then
   DEVICE=/dev/ttyAMA0
 fi
 if [ -f /dev/ttyS0 ]; then
   DEVICE=/dev/ttyS0
 fi
fi

DIALOUTGROUPID=$(stat --printf='%g' $DEVICE)
DIALOUTGROUPID=${DIALOUTGROUPID:-20}
if [ "$DIALOUTGROUPID" != 20 ]; then
  sudo groupmod -o -g "$DIALOUTGROUPID" dialout
fi

if [ "$DECONZ_VNC_MODE" != 0 ]; then

  if [ "$DECONZ_VNC_PORT" -lt 5900 ]; then
    echo "[marthoc/deconz] ERROR - VNC port must be 5900 or greater!"
    exit 1
  fi

  DECONZ_VNC_DISPLAY=:$(($DECONZ_VNC_PORT - 5900))
  echo "[marthoc/deconz] VNC port: $DECONZ_VNC_PORT"

  if [ ! -e /opt/deCONZ/vnc ]; then
    mkdir /opt/deCONZ/vnc
  fi

  sudo -u deconz ln -sf /opt/deCONZ/vnc /home/deconz/.vnc
  chown deconz:deconz /opt/deCONZ -R

  # Set VNC password
  if [ "$DECONZ_VNC_PASSWORD_FILE" != 0 ] && [ -f "$DECONZ_VNC_PASSWORD_FILE" ]; then
      DECONZ_VNC_PASSWORD=$(cat $DECONZ_VNC_PASSWORD_FILE)
  fi

  echo "$DECONZ_VNC_PASSWORD" | tigervncpasswd -f > /opt/deCONZ/vnc/passwd
  chmod 600 /opt/deCONZ/vnc/passwd
  chown deconz:deconz /opt/deCONZ/vnc/passwd

  # Cleanup previous VNC session data
  sudo -u deconz tigervncserver -kill "$DECONZ_VNC_DISPLAY"

  # Set VNC security
  sudo -u deconz tigervncserver -SecurityTypes VncAuth,TLSVnc "$DECONZ_VNC_DISPLAY"

  # Export VNC display variable
  export DISPLAY=$DECONZ_VNC_DISPLAY

  if [ "$DECONZ_NOVNC_PORT" = 0 ]; then
    echo "[marthoc/deconz] noVNC Disabled"
  else
    if [ "$DECONZ_NOVNC_PORT" -lt 6080 ]; then
      echo "[marthoc/deconz] ERROR - NOVNC port must be 6080 or greater!"
      exit 1
    fi

    # Assert valid SSL certificate
    NOVNC_CERT="/opt/deCONZ/vnc/novnc.pem"
    if [ -f "$NOVNC_CERT" ]; then
      openssl x509 -noout -in "$NOVNC_CERT" -checkend 0 > /dev/null
      if [ $? != 0 ]; then
        echo "[marthoc/deconz] The noVNC SSL certificate has expired; generating a new certificate now."
        rm "$NOVNC_CERT"
      fi
    fi
    if [ ! -f "$NOVNC_CERT" ]; then
      openssl req -x509 -nodes -newkey rsa:2048 -keyout "$NOVNC_CERT" -out "$NOVNC_CERT" -days 365 -subj "/CN=deconz"
    fi

    chown deconz:deconz $NOVNC_CERT

    #Start noVNC
    sudo -u deconz websockify -D --web=/usr/share/novnc/ --cert="$NOVNC_CERT" $DECONZ_NOVNC_PORT localhost:$DECONZ_VNC_PORT
    echo "[marthoc/deconz] NOVNC port: $DECONZ_NOVNC_PORT"
  fi

else
  echo "[marthoc/deconz] VNC Disabled"
  DECONZ_OPTS="$DECONZ_OPTS -platform minimal"
fi

if [ "$DECONZ_DEVICE" != 0 ]; then
  DECONZ_OPTS="$DECONZ_OPTS --dev=$DECONZ_DEVICE"
fi

if [ "$DECONZ_UPNP" != 1 ]; then
  DECONZ_OPTS="$DECONZ_OPTS --upnp=0"
fi

chown deconz:deconz /opt/deCONZ -R

sudo -u deconz /usr/bin/deCONZ $DECONZ_OPTS
