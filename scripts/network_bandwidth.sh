#!/usr/bin/env bash

# INTERVAL is equal to 1s because we want to express the bandwidth in sec
readonly INTERVAL=1

# UPLOAD and DOWNLOAD index
readonly UPLOAD=0
readonly DOWNLOAD=1

# SIZE index are the multiple of the unit byte and value the internationally recommended unit symbol in sec
readonly SIZE=(
  [1]='B/s'
  [1024]='kB/s'
  [1048576]='MB/s'
  [1073741824]='GB/s'
)

# interface_get try to automaticaly get the used interface if network_name is empty
interface_get() {
  name="$(tmux show-option -gqv "@dracula-network-bandwidth")"

  if [[ -z $name ]]; then
    case "$(uname -s)" in
    Linux)
      if type ip >/dev/null; then
        name="$(ip -o route get 192.168.0.0 | awk '{print $5}')"
      fi
      ;;
    esac
  fi

  echo "$name"
}

# ref: https://github.com/xamut/tmux-network-bandwidth/blob/63c6b3283d537d9b86489c13b99ba0c65e0edac8/scripts/network-bandwidth.sh#L7C1-L21C2
# get_bandwidth_for_osx return the number of bytes exchanged for tx and rx on macOS
get_bandwidth_for_osx() {
  netstat -ibn | awk 'FNR > 1 {
    interfaces[$1 ":bytesReceived"] = $(NF-4);
    interfaces[$1 ":bytesSent"]     = $(NF-1);
  } END {
    for (itemKey in interfaces) {
      split(itemKey, keys, ":");
      interface = keys[1]
      dataKind = keys[2]
      sum[dataKind] += interfaces[itemKey]
    }

    print sum["bytesReceived"], sum["bytesSent"]
  }'
}

# interface_bytes give interface name and signal tx/rx return Bytes
interface_bytes() {
  cat "/sys/class/net/$1/statistics/$2_bytes"
}

# get_bandwidth return the number of bytes exchanged for tx and rx
get_bandwidth() {
  local upload download new_upload new_download

  if [[ "$(uname -s)" == "Linux" ]]; then
    upload="$(interface_bytes "$1" "tx")"
    download="$(interface_bytes "$1" "rx")"

    # Wait for interval to calculate the difference
    sleep "$INTERVAL"

    new_upload="$(interface_bytes "$1" "tx")"
    new_download="$(interface_bytes "$1" "rx")"
  elif [[ "$(uname -s)" == "Darwin" ]]; then
    read upload download <<<"$(get_bandwidth_for_osx)"

    # Wait for interval to calculate the difference
    sleep "$INTERVAL"

    read new_upload new_download <<<"$(get_bandwidth_for_osx)"
  fi

  # Calculate bandwidth
  upload=$((new_upload - upload))
  download=$((new_download - download))

  # Set to 0 by default, useful for non-existent interface
  echo "${upload:-0} ${download:-0}"
}

# bandwidth_to_unit convert bytes into its highest unit and add unit symbol in sec
bandwidth_to_unit() {
  local size=1
  for i in "${!SIZE[@]}"; do
    if (($1 < i)); then
      break
    fi

    size="$i"
  done

  local result="0.00"
  if (($1 != 0)); then
    result="$(bc <<<"scale=2; $1 / $size")"
  fi

  echo "$result ${SIZE[$size]}"
}

main() {
  counter=0
  bandwidth=()

  network_name=""
  show_interface="$(tmux show-option -gqv "@dracula-network-bandwidth-show-interface")"
  interval_update="$(tmux show-option -gqv "@dracula-network-bandwidth-interval")"

  if [[ -z $interval_update ]]; then
    interval_update=0
  fi

  if ! command -v bc &> /dev/null
  then
    echo "command bc could not be found!"
    exit 1
  fi

  while true; do
    if ((counter == 0)); then
      counter=60
      network_name="$(interface_get)"
    fi

    IFS=" " read -ra bandwidth <<<"$(get_bandwidth "$network_name")"

    if [[ $show_interface == "true" ]]; then echo -n "[$network_name] "; fi
    echo "↓ $(bandwidth_to_unit "${bandwidth[$DOWNLOAD]}") • ↑ $(bandwidth_to_unit "${bandwidth[$UPLOAD]}")"

    ((counter = counter - 1))
    sleep "$interval_update"
  done
}

#run main driver
main
