#!/bin/bash

# svgstat.sh - Bash script that displays system information in an SVG graph.
# The script can be used with xfce4-genmon-plugin to show a graph onto the panel.
#
# https://github.com/thomasedoff/svgstat.sh

# General settings
disk_mount_point="/home/"
disk_device="nvme1n1"
net_device="enp6s0"
history_file="/tmp/svgstat-history.txt"

# Data to include
declare -a keys=(
	cpu_load
	mem_usage
	disk_usage
	net_rxtx
	disk_rw
	power
	temp
)

# Max values (for percentages)
declare -A values_max=(
	[net_tx_mbps]=50
	[net_rx_mbps]=50
	[disk_r_mbps]="auto"
	[disk_w_mbps]="auto"
	[cpu_w]="auto"
	[gpu_w]="auto"
)

# SVG dimensions
width=37
height=30
margin=1
 
get_cpu_load() {
	cpu_load=$(cut -d' ' -f1 < /proc/loadavg)
	cpu_cores=$(grep -c ^processor /proc/cpuinfo)
	cpu_load_pcent=$(get_pcent "$cpu_load" "$cpu_cores")
		
	values_pcent+=("$cpu_load_pcent")
	tooltip+="cpu_load: $cpu_load ($cpu_load_pcent%)\n"
}

get_mem_usage() {
	read -r mem_total_gb mem_usage_gb mem_usage_pcent < <(free --mega -t | \
		awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')
		
	values_pcent+=("$mem_usage_pcent")
	tooltip+="mem_usage: $mem_usage_gb/$mem_total_gb GiB ($mem_usage_pcent%)\n"
}

get_disk_usage() {
	read -r disk_size disk_usage disk_usage_pcent < <(df -BG --output=size,used,pcent "$disk_mount_point" | \
		awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')
		
	values_pcent+=("$disk_usage_pcent")
	tooltip+="disk_usage: $disk_usage/$disk_size GiB ($disk_usage_pcent%)\n\n"
}

get_net_rxtx() {
	read -r net_date_old net_tx_mb_old net_rx_mb_old < /tmp/svgstat-net.txt
	read -r net_rx_mb net_tx_mb < <(awk '{printf "%f ", $1*8/10^6}' \
		 /sys/class/net/$net_device/statistics/rx_bytes \
		 /sys/class/net/$net_device/statistics/tx_bytes)
	
	interval=$((date-net_date_old))
	net_rx_mbps=$(get_rate "$net_rx_mb" "$net_rx_mb_old" "$interval")
	net_tx_mbps=$(get_rate "$net_tx_mb" "$net_tx_mb_old" "$interval")
	net_rx_pcent=$(get_pcent "$net_rx_mbps" "${values_max[net_rx_mbps]}")
	net_tx_pcent=$(get_pcent "$net_tx_mbps" "${values_max[net_tx_mbps]}")
	
	values+=([net_rx_mbps]="$net_rx_mbps" [net_tx_mbps]="$net_tx_mbps")
	values_pcent+=("$net_rx_pcent" "$net_tx_pcent")
	tooltip+="net_rx: $net_rx_mbps/${values_max[net_rx_mbps]} Mbps ($net_rx_pcent%)\n"
	tooltip+="net_tx: $net_tx_mbps/${values_max[net_tx_mbps]} Mbps ($net_tx_pcent%)\n\n"

	echo "$date $net_tx_mb $net_rx_mb" > /tmp/svgstat-net.txt
}

get_disk_rw() {
	read -r disk_date_old disk_r_mb_old disk_w_mb_old < /tmp/svgstat-disk.txt
	read -r disk_r_mb disk_w_mb < <(awk '{printf "%d %d", $3*512/1024/1024, $7*512/1024/1024 }' \
		/sys/block/$disk_device/stat)
	
	interval=$((date-disk_date_old))
	disk_r_mbps=$(get_rate "$disk_r_mb" "$disk_r_mb_old" "$interval")
	disk_w_mbps=$(get_rate "$disk_w_mb" "$disk_w_mb_old" "$interval")
	disk_r_pcent=$(get_pcent "$disk_r_mbps" "${values_max[disk_r_mbps]}")
	disk_w_pcent=$(get_pcent "$disk_w_mbps" "${values_max[disk_w_mbps]}")
	
	values+=([disk_r_mbps]="$disk_r_mbps" [disk_w_mbps]="$disk_w_mbps")
	values_pcent+=("$disk_r_pcent" "$disk_w_pcent")
	tooltip+="disk_r: $disk_r_mbps/${values_max[disk_r_mbps]} MBps ($disk_r_pcent%)\n"
	tooltip+="disk_w: $disk_w_mbps/${values_max[disk_w_mbps]} MBps ($disk_w_pcent%)\n\n"

	echo "$date $disk_r_mb $disk_w_mb" > /tmp/svgstat-disk.txt
}

get_power() {
	# Tested only on AMD Ryzen! Root privileges and an external tool are required to read these values.
	# https://github.com/djselbeck/rapl-read-ryzen
	if [[ "$EUID" -eq 0 ]]; then
		cpu_w=$(/usr/bin/rapl-read-ryzen | awk '/Core sum:/{gsub("W", ""); printf "%d", $3}')
		gpu_w=$(awk '/(average GPU)/{printf "%d", $0}' /sys/kernel/debug/dri/0/amdgpu_pm_info)
		cpu_w_pcent=$(get_pcent "$cpu_w" "${values_max[cpu_w]}")
		gpu_w_pcent=$(get_pcent "$gpu_w" "${values_max[gpu_w]}")
	fi
	
	values+=([cpu_w]="$cpu_w" [gpu_w]="$gpu_w")
	values_pcent+=("$cpu_w_pcent" "$gpu_w_pcent")
	tooltip+="cpu_power: $cpu_w/${values_max[cpu_w]} W ($cpu_w_pcent%)\n"
	tooltip+="gpu_power: $gpu_w/${values_max[gpu_w]} W ($gpu_w_pcent%)\n\n"
}

get_temp() {
	# Order may not be reliable
	read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
		/sys/class/hwmon/hwmon3/temp1_input \
		/sys/class/hwmon/hwmon2/temp2_input \
		/sys/class/hwmon/hwmon0/temp1_input)
	
	values_pcent+=("$cpu_temp" "$gpu_temp" "$ssd_temp")
	tooltip+="cpu_temp: $cpu_temp C\n"
	tooltip+="gpu_temp: $gpu_temp C\n"
	tooltip+="ssd_temp: $ssd_temp C"
}

get_values_max() {
	source /tmp/svgstat-max.txt || declare -Ag values_max_old

	for i in "${!values_max[@]}"; do
		if [[ "${values_max[$i]}" == "auto" ]]; then
			values_max[$i]=${values_max_old[$i]}
		fi
		
		if [[ -z "${values_max[$i]}" ]]; then
			values_max[$i]=0
		fi
	done
}

set_values_max() {
	for i in "${!values[@]}"; do
		if [[ "${values[$i]}" -ge "${values_max[$i]}" ]]; then
			values_max_old[$i]="${values[$i]}"
		fi
	done

	declare -Ap values_max_old | sed 's/ -A/&g/' > /tmp/svgstat-max.txt
}

get_pcent() {
	if [[ "$2" -le 0 ]]; then
		echo "0"
	else
		awk -v value="$1" -v total="$2" 'BEGIN {printf "%d", value/total*100}'
	fi
	
	exit
}

get_rate() {
	if [[ "$3" -le 0 ]]; then
		echo "0"
	else
		awk -v new="$1" -v old="$2" -v interval="$3" 'BEGIN {printf "%d", (new-old)/interval}'
	fi
}

write_history() {
	values_joined=$(printf ",%s" "${values[@]}")
	echo "${date}${values_joined}" >> "$history_file"
}

draw_elements() {
	local width=$(((width-margin)/${#values_pcent[@]}-margin))
	for ((i=0; i<${#values_pcent[@]}; i++)); do
		local x=$(((width+margin)*i))
		local height=$((((${values_pcent[$i]%.*}+5)/10)*10))
		
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
declare -A values=()

get_values_max
for i in "${keys[@]}"; do
	"get_${i}";
done
set_values_max
create_svg
#write_history

echo -e "<img>/tmp/svgstat-graph.svg</img><tool>${tooltip}</tool>"
