#!/bin/bash

# svgstat.sh - Bash script that displays system information in an SVG graph.
# The script can be used with xfce4-genmon-plugin to show a graph onto the panel.

# General settings
disk_mount_point="/home/"
disk_device="nvme1n1"
net_tx_mbps_max=50
net_rx_mbps_max=50
disk_r_mbps_max=6000
disk_w_mbps_max=4500

# SVG dimensions
width=40
height=30
margin=1

get_cpu_load() {
  cpu_load=$(cut -d' ' -f1 < /proc/loadavg)
  cpu_load_pcent=$(awk -v cpu_cores="$(grep -c ^processor /proc/cpuinfo)" -v cpu_load="$cpu_load" \
    'BEGIN {printf "%d", cpu_load/cpu_cores*100}')
}

get_mem_usage() {
  read -r mem_total_gb mem_usage_gb mem_usage_pcent < <(free --mega -t | \
    awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')
}

get_disk_usage() {
  read -r disk_size disk_usage disk_usage_pcent < <(df -BG --output=size,used,pcent "$disk_mount_point" | \
    awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')
}

get_net_rxtx() {
  read -r net_date_old net_tx_mb_old net_rx_mb_old < /tmp/svgstat-net.txt
  read -r net_rx_mb net_tx_mb < <(awk '{printf "%f ", $1*8/1000000}' \
     /sys/class/net/enp6s0/statistics/rx_bytes \
     /sys/class/net/enp6s0/statistics/tx_bytes)
  ca
  interval=$((date-net_date_old))
  if [[ $interval -ne 0 && -f /tmp/net.txt ]]; then
    net_rx_mbps=$(awk -v net_rx_mb="$net_rx_mb" -v net_rx_mb_old="$net_rx_mb_old" -v interval="$interval" \
      'BEGIN {printf "%.2f", (net_rx_mb-net_rx_mb_old)/interval}')
    net_tx_mbps=$(awk -v net_tx_mb="$net_tx_mb" -v net_tx_mb_old="$net_tx_mb_old" -v interval="$interval" \
      'BEGIN {printf "%.2f", (net_tx_mb-net_tx_mb_old)/interval}')
      
    net_rx_pcent=$(awk -v net_rx_mbps="$net_rx_mbps" -v net_rx_mbps_max="$net_rx_mbps_max" \
      'BEGIN {printf "%d", net_rx_mbps/net_rx_mbps_max*100}')
    net_tx_pcent=$(awk -v net_tx_mbps="$net_tx_mbps" -v net_tx_mbps_max="$net_tx_mbps_max" \
      'BEGIN {printf "%d", net_tx_mbps/net_tx_mbps_max*100}')
  fi
  
  echo "$date $net_tx_mb $net_rx_mb" > /tmp/svgstat-net.txt
}

get_disk_rw() {
  read -r disk_date_old disk_r_mb_old disk_w_mb_old < /tmp/svgstat-disk.txt
  read -r disk_r_mb disk_w_mb < <(awk '{printf "%d %d", $3*512/1024/1024, $7*512/1024/1024 }' \
    /sys/block/$disk_device/stat)
  
  interval=$((date-disk_date_old))
  if [[ $interval -ne 0 && -f /tmp/disk.txt ]]; then
    disk_r_mbps=$(awk -v disk_r_mb="$disk_r_mb" \
      -v disk_r_mb_old="$disk_r_mb_old" -v interval="$interval" \
      'BEGIN {printf "%d", (disk_r_mb-disk_r_mb_old)/interval}')
    disk_w_mbps=$(awk -v disk_w_mb="$disk_w_mb" \
      -v disk_w_mb_old="$disk_w_mb_old" -v interval="$interval" \
      'BEGIN {printf "%d", (disk_w_mb-disk_w_mb_old)/interval}')
    
    disk_r_pcent=$(awk -v disk_r_mbps="$disk_r_mbps" -v disk_r_mbps_max="$disk_r_mbps_max" \
      'BEGIN {printf "%d", disk_r_mbps/disk_r_mbps_max*100}')
    disk_w_pcent=$(awk -v disk_w_mbps="$disk_w_mbps" -v disk_w_mbps_max="$disk_w_mbps_max" \
      'BEGIN {printf "%d", disk_w_mbps/disk_w_mbps_max*100}')
  fi
  
  echo "$date $disk_r_mb $disk_w_mb" > /tmp/svgstat-disk.txt
}

get_temps() {
  read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
    /sys/class/hwmon/hwmon3/temp1_input \
    /sys/class/hwmon/hwmon2/temp2_input \
    /sys/class/hwmon/hwmon0/temp1_input)
}

draw_elements() {
  local width=$(((width-margin)/${#values[@]}-margin))
  for ((i=0; i<${#values[@]}; i++)); do
    local x=$(((width+margin)*i))
    local val=$((((${values[$i]%.*}+5)/10)*10))
    
    bars+="<rect class='bar--$i' width='$width' height='${val}%' x='$x' y='0' />"
  done
  
  for i in {0..100..10}; do
    lines+="<line class='line' x1='0' y1='${i}%' x2='100%' y2='${i}%' />"
  done
}

date=$(date +%s)

get_cpu_load
get_mem_usage
get_disk_usage
get_net_rxtx
get_disk_rw
get_temps

declare -a values=(
  "$cpu_load_pcent"
  "$mem_usage_pcent"
  "$disk_usage_pcent"
  0
  "$net_rx_pcent" 
  "$net_tx_pcent" 
  0
  "$disk_r_pcent" 
  "$disk_w_pcent"
  0
  "$cpu_temp"
  "$gpu_temp" 
  "$ssd_temp"
)

draw_elements

cat << EOF > /tmp/svgstat-graph.svg
<svg version="1.1"
  width="$width"
  height="$height"
  xmlns="http://www.w3.org/2000/svg">

  <style>
    .container { fill: #000; }
    .bar--0 { fill: #A93226; }
    .bar--1 { fill: #CB4335; }
    .bar--2 { fill: #884EA0; }
    .bar--3 { fill: #7D3C98; }
    .bar--4 { fill: #2471A3; }
    .bar--5 { fill: #2E86C1; }
    .bar--6 { fill: #17A589; }
    .bar--7 { fill: #138D75; }
    .bar--8 { fill: #229954; }
    .bar--9 { fill: #28B463; }
    .bar--10 { fill: #D4AC0D; }
    .bar--11 { fill: #D68910; }
    .bar--12 { fill: #CA6F1E; }
    .bar--13 { fill: #BA4A00; }
    .line { stroke: #000; stroke-width: $margin }
  </style>
  
  <rect class="container" width="$width" height="$height" />
  <svg width="$((width-margin*2))" height="$((height-margin*2))"
    x="$margin" y="$margin" transform="scale(1,-1) translate(0,-$height)">
    <g>$bars</g>
    <g>$lines</g>
  </svg>
</svg>
EOF

cat <<- EOF
<img>/tmp/svgstat-graph.svg</img>
<tool>cpu_load: $cpu_load ($cpu_load_pcent%)
mem_usage: $mem_usage_gb/$mem_total_gb GiB ($mem_usage_pcent%)
disk_usage: $disk_usage/$disk_size GiB ($disk_usage_pcent%)

net_rx: $net_rx_mbps/$net_rx_mbps_max Mbps ($net_rx_pcent%)
net_tx: $net_tx_mbps/$net_tx_mbps_max Mbps ($net_tx_pcent%)

disk_r: $disk_r_mbps/$disk_r_mbps_max MBps ($disk_r_pcent%)
disk_w: $disk_w_mbps/$disk_w_mbps_max MBps ($disk_w_pcent%)

cpu_temp: $cpu_temp C
gpu_temp: $gpu_temp C
ssd_temp: $ssd_temp C</tool>"
EOF
