#!/bin/sh
# syno-fan.sh — balanced fan control for DS115j based on SoC temperature.
#
# Hysteresis is in °C (millidegrees), not pwm. Crossing 58↔59 °C used to
# flip pwm 110↔145 every poll because |110-145| ≥ the old pwm delta.
# Idle is pwm 25 (~1000 rpm). Never write pwm 0.
set -u

INTERVAL=20
HYST_MDEG=2000          # 2 °C stickiness on the falling edge
PWM_MIN=25              # ~1000 rpm; never 0
PWM_FALLBACK=65         # sensor missing
OVERHEAT_ON=75000       # ≥75 °C → MCU alarm once per episode
OVERHEAT_OFF=70000      # ≤70 °C → re-arm
MCU=/usr/local/sbin/syno-mcu.sh

temp_to_pwm() {
  t=$1
  if   [ "$t" -le 45000 ]; then echo 25
  elif [ "$t" -le 52000 ]; then echo 65
  elif [ "$t" -le 58000 ]; then echo 110
  elif [ "$t" -le 63000 ]; then echo 145
  elif [ "$t" -le 68000 ]; then echo 190
  elif [ "$t" -le 73000 ]; then echo 230
  else echo 255; fi
}

clamp_pwm() {
  p=$1
  [ "$p" -lt "$PWM_MIN" ] && p=$PWM_MIN
  echo "$p"
}

# Rising edge: use live temp. Falling edge: pretend +HYST_MDEG so we only
# drop a band after cooling 2 °C below the edge that raised us.
pwm_with_hyst() {
  temp=$1
  prev=${2-}
  up=$(temp_to_pwm "$temp")
  if [ -z "$prev" ]; then
    clamp_pwm "$up"
    return
  fi
  down=$(temp_to_pwm $((temp + HYST_MDEG)))
  if [ "$up" -gt "$prev" ]; then
    clamp_pwm "$up"
  elif [ "$down" -lt "$prev" ]; then
    clamp_pwm "$down"
  else
    echo "$prev"
  fi
}

# prints: <new_flag> [TRIGGER|CLEAR]
alarm_step() {
  temp=$1
  active=$2
  if [ "$temp" -ge "$OVERHEAT_ON" ] && [ "$active" -eq 0 ]; then
    echo "1 TRIGGER"
  elif [ "$temp" -le "$OVERHEAT_OFF" ] && [ "$active" -eq 1 ]; then
    echo "0 CLEAR"
  else
    echo "$active"
  fi
}

find_pwm1() {
  for d in /sys/class/hwmon/hwmon*; do
    [ -e "$d/pwm1" ] && [ -e "$d/fan1_target" ] && { echo "$d/pwm1"; return 0; }
  done
  return 1
}

find_temp() {
  for d in /sys/class/hwmon/hwmon*; do
    [ -e "$d/temp1_input" ] && [ -e "$d/pwm1" ] && continue
    [ -r "$d/temp1_input" ] && { echo "$d/temp1_input"; return 0; }
  done
  [ -r /sys/class/hwmon/hwmon0/temp1_input ] && {
    echo /sys/class/hwmon/hwmon0/temp1_input
    return 0
  }
  return 1
}

self_test() {
  fail=0
  expect() {
    got=$1 want=$2 msg=$3
    if [ "$got" != "$want" ]; then
      echo "FAIL $msg: got=$got want=$want"
      fail=1
    else
      echo "OK   $msg ($got)"
    fi
  }

  expect "$(temp_to_pwm 45000)" 25 "idle band"
  expect "$(temp_to_pwm 58000)" 110 "58 C band"
  expect "$(temp_to_pwm 59000)" 145 "59 C band"
  expect "$(clamp_pwm 0)" 25 "never pwm 0"

  p=$(pwm_with_hyst 57000 "")
  expect "$p" 110 "first sample 57 C"
  p=$(pwm_with_hyst 58000 "$p")
  expect "$p" 110 "58 C must not hunt up from 57"
  p=$(pwm_with_hyst 59000 "$p")
  expect "$p" 145 "59 C may rise"
  p=$(pwm_with_hyst 58000 "$p")
  expect "$p" 145 "58 C must not hunt down from 59"
  p=$(pwm_with_hyst 57000 "$p")
  expect "$p" 145 "57 C still sticky after 59"
  p=$(pwm_with_hyst 56000 "$p")
  expect "$p" 110 "56 C (2 C hyst) may drop"

  # overheat path — logic only, no MCU, no thermal stress
  r=$(alarm_step 74000 0)
  expect "$r" 0 "74 C no alarm"
  r=$(alarm_step 75000 0)
  expect "$r" "1 TRIGGER" "75 C triggers once"
  r=$(alarm_step 80000 1)
  expect "$r" 1 "80 C stays latched"
  r=$(alarm_step 71000 1)
  expect "$r" 1 "71 C still latched"
  r=$(alarm_step 70000 1)
  expect "$r" "0 CLEAR" "70 C clears"
  r=$(alarm_step 75000 0)
  expect "$r" "1 TRIGGER" "re-arms on next overheat"

  if [ "$fail" -ne 0 ]; then
    echo "syno-fan self-test FAILED"
    exit 1
  fi
  echo "syno-fan self-test PASSED"
  exit 0
}

if [ "${1-}" = "--self-test" ]; then
  self_test
fi

prev_pwm=""
alarm_active=0

# hwmon gpio-fan may appear after udev; wait rather than write into a hole
i=0
PWM1=""
while [ "$i" -lt 120 ]; do
  PWM1=$(find_pwm1) || PWM1=""
  if [ -n "$PWM1" ] && [ -w "$PWM1" ]; then
    break
  fi
  sleep 0.5
  i=$((i + 1))
done
if [ -z "$PWM1" ] || [ ! -w "$PWM1" ]; then
  echo "syno-fan: FATAL pwm1 not writable after wait" >&2
  exit 1
fi
FAN=$(dirname "$PWM1")
echo "syno-fan: using $PWM1"

while true; do
  TEMP=$(find_temp) || TEMP=""
  if [ -z "$TEMP" ] || [ ! -r "$TEMP" ]; then
    echo "$PWM_FALLBACK" > "$PWM1" 2>/dev/null || true
    echo "syno-fan: WARN temp sensor missing, pwm=$PWM_FALLBACK"
    sleep "$INTERVAL"
    continue
  fi

  temp=$(cat "$TEMP")
  desired=$(pwm_with_hyst "$temp" "$prev_pwm")

  if [ "$desired" != "$prev_pwm" ]; then
    if echo "$desired" > "$PWM1" 2>/dev/null; then
      target=$(cat "$FAN/fan1_target" 2>/dev/null || echo "?")
      echo "syno-fan: $((temp / 1000))°C  ->  pwm=$desired  fan1_target=$target"
      prev_pwm=$desired
    else
      echo "syno-fan: WARN pwm write failed (fan not ready?)" >&2
    fi
  fi

  ar=$(alarm_step "$temp" "$alarm_active")
  new=${ar%% *}
  ev=${ar#* }
  if [ "$ev" = "TRIGGER" ]; then
    if [ -x "$MCU" ]; then
      "$MCU" alarm >/dev/null 2>&1 || echo "syno-fan: WARN MCU alarm send failed" >&2
    fi
    alarm_active=1
    echo "syno-fan: overheat alarm triggered at $((temp / 1000))°C"
  elif [ "$ev" = "CLEAR" ]; then
    alarm_active=0
    echo "syno-fan: overheat alarm cleared at $((temp / 1000))°C"
  else
    alarm_active=$new
  fi

  sleep "$INTERVAL"
done
