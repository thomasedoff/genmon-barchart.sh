#!/bin/bash

# svgstat.sh - Bash script that displays system information in an SVG graph.
# The script can be used with xfce4-genmon-plugin to show a graph onto the panel.
#
# https://github.com/thomasedoff/svgstat.sh

# General settings
disk_mount_point="/home/"
disk_device="nvme1n1"
net_device="enp6s0"
net_tx_mbps_max=50
net_rx_mbps_max=50
disk_r_mbps_max=6000
disk_w_mbps_max=4500
cpu_w_max=200
gpu_w_max=350
history_file="/tmp/svgstat-history.txt"

# SVG dimensions
width=37
height=30
margin=1

get_cpu_load() {
	cpu_load=$(cut -d' ' -f1 < /proc/loadavg)
	cpu_cores=$(grep -c ^processor /proc/cpuinfo)
	cpu_load_pcent=$(get_pcent "$cpu_load" "$cpu_cores")
		
	values+=("$cpu_load_pcent")
	tooltip+="cpu_load: $cpu_load ($cpu_load_pcent%)\n"
}

get_mem_usage() {
	read -r mem_total_gb mem_usage_gb mem_usage_pcent < <(free --mega -t | \
		awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')
		
	values+=("$mem_usage_pcent")
	tooltip+="mem_usage: $mem_usage_gb/$mem_total_gb GiB ($mem_usage_pcent%)\n"
}

get_disk_usage() {
	read -r disk_size disk_usage disk_usage_pcent < <(df -BG --output=size,used,pcent "$disk_mount_point" | \
		awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')
		
	values+=("$disk_usage_pcent")
	tooltip+="disk_usage: $disk_usage/$disk_size GiB ($disk_usage_pcent%)\n\n"
}

get_net_rxtx() {
	read -r net_date_old net_tx_mb_old net_rx_mb_old < /tmp/svgstat-net.txt
	read -r net_rx_mb net_tx_mb < <(awk '{printf "%f ", $1*8/10^6}' \
		 /sys/class/net/$net_device/statistics/rx_bytes \
		 /sys/class/net/$net_device/statistics/tx_bytes)
	
	interval=$((date-net_date_old))
	if [[ $interval -ne 0 && -f /tmp/net.txt ]]; then
		net_rx_mbps=$(get_rate "$net_rx_mb" "$net_rx_mb_old" "$interval")
		net_tx_mbps=$(get_rate "$net_tx_mb" "$net_tx_mb_old" "$interval")
		net_rx_pcent=$(get_pcent "$net_rx_mbps" "$net_rx_mbps_max")
		net_tx_pcent=$(get_pcent "$net_tx_mbps" "$net_tx_mbps_max")
	fi
	
	values+=("$net_rx_pcent" "$net_tx_pcent")
	tooltip+="net_rx: $net_rx_mbps/$net_rx_mbps_max Mbps ($net_rx_pcent%)\n"
	tooltip+="net_tx: $net_tx_mbps/$net_tx_mbps_max Mbps ($net_tx_pcent%)\n\n"

	echo "$date $net_tx_mb $net_rx_mb" > /tmp/svgstat-net.txt
}

get_disk_rw() {
	read -r disk_date_old disk_r_mb_old disk_w_mb_old < /tmp/svgstat-disk.txt
	read -r disk_r_mb disk_w_mb < <(awk '{printf "%d %d", $3*512/1024/1024, $7*512/1024/1024 }' \
		/sys/block/$disk_device/stat)
	
	interval=$((date-disk_date_old))
	if [[ $interval -ne 0 && -f /tmp/disk.txt ]]; then
		disk_r_mbps=$(get_rate "$disk_r_mb" "$disk_r_mb_old" "$interval")
		disk_w_mbps=$(get_rate "$disk_w_mb" "$disk_w_mb_old" "$interval")
		disk_r_pcent=$(get_pcent "$disk_r_mbps" "$disk_r_mbps_max")
		disk_w_pcent=$(get_pcent "$disk_w_mbps" "$disk_w_mbps_max")
	fi
	
	values+=("$disk_r_pcent" "$disk_w_pcent")
	tooltip+="disk_r: $disk_r_mbps/$disk_r_mbps_max MBps ($disk_r_pcent%)\n"
	tooltip+="disk_w: $disk_w_mbps/$disk_w_mbps_max MBps ($disk_w_pcent%)\n\n"

	echo "$date $disk_r_mb $disk_w_mb" > /tmp/svgstat-disk.txt
}

get_power() {
	# Root privileges are required to read these files
	if [[ "$EUID" -eq 0 ]]; then
		# https://github.com/djselbeck/rapl-read-ryzen
		cpu_w=$(/usr/bin/rapl-read-ryzen | awk '/Core sum:/{gsub("W", ""); printf "%.1f", $3}')
		gpu_w=$(sed -n -e 's/^\t\(.*\) W (average GPU)/\1/p' /sys/kernel/debug/dri/0/amdgpu_pm_info)
		cpu_w_pcent=$(get_pcent "$cpu_w" "$cpu_w_max")
		gpu_w_pcent=$(get_pcent "$gpu_w" "$gpu_w_max")
	fi
	
	values+=("$cpu_w_pcent" "$gpu_w_pcent")
	tooltip+="cpu_power: $cpu_w/$cpu_w_max W ($cpu_w_pcent%)\n"
	tooltip+="gpu_power: $gpu_w/$gpu_w_max W ($gpu_w_pcent%)\n\n"
}

get_temps() {
	read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
		/sys/class/hwmon/hwmon3/temp1_input \
		/sys/class/hwmon/hwmon2/temp2_input \
		/sys/class/hwmon/hwmon0/temp1_input)
	
	values+=("$cpu_temp" "$gpu_temp" "$ssd_temp")
	tooltip+="cpu_temp: $cpu_temp C\n"
	tooltip+="gpu_temp: $gpu_temp C\n"
	tooltip+="ssd_temp: $ssd_temp C"
}

write_history() {
	if [[ -n "$history_file" ]]; then
		values_joined=$(printf ",%s" "${values[@]}")
		echo "${date}${values_joined}" >> "$history_file"
	fi
}

get_pcent() {
	awk -v value="$1" -v total="$2" 'BEGIN {printf "%d", value/total*100}'
}

get_rate() {
	awk -v new="$1" -v old="$2" -v interval="$3" 'BEGIN {printf "%d", (new-old)/interval}'
}

draw_elements() {
	local width=$(((width-margin)/${#values[@]}-margin))
	for ((i=0; i<${#values[@]}; i++)); do
		local x=$(((width+margin)*i))
		local height=$((((${values[$i]%.*}+5)/10)*10))
		
		bars+="<rect class='bar--$i' width='$width' height='${height}%' x='$x' y='0' />"
	done
	
	for i in {0..100..10}; do
		lines+="<line class='line' x1='0' y1='${i}%' x2='100%' y2='${i}%' />"
	done
}

create_svg() {
	draw_elements

	cat <<- EOF > /tmp/svgstat-graph.svg
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
}

date=$(date +%s)
declare -a values=()

# What to do
get_cpu_load
get_mem_usage
get_disk_usage
get_net_rxtx
get_disk_rw
get_power
get_temps
create_svg
#write_history

echo -e "<img>/tmp/svgstat-graph.svg</img><tool>${tooltip}</tool>"
