#!/bin/bash

# genmon-barchart.sh - A GenMon script that displays system information.
# The script can be used with xfce4-genmon-plugin to show a bar chart on the panel.
#
# https://github.com/thomasedoff/genmon-barchart.sh

# General settings
disk_mount_point="/home/"
disk_device="nvme1n1"
net_device="enp6s0"
values_file="/tmp/genmon-barchart-values.txt"

# Functions
declare -a bars=(
	#num_warn
	num_users
	num_procs
	cpu_load
	mem_usage
	disk_usage
	net_rxtx
	net_skt
	disk_rw
	#power
	#temp
)

# Max values - If set to auto, the percentages will be based on the highest value recorded.
declare -A values_max=(
	[num_warn]="auto"
	[num_users]="auto"
	[num_procs]="auto"
	[cpu_freq]="auto"
	[cpu_load]="auto"
	[net_rx_mbit_s]="auto"
	[net_tx_mbit_s]="auto"
	[net_skt_tcp]="auto"
	[net_skt_udp]="auto"
	[disk_r_mbyte_s]="auto"
	[disk_w_mbyte_s]="auto"
	[cpu_w]="auto"
	[gpu_w]="auto"
	[cpu_temp]=100
	[gpu_temp]=100
	[ssd_temp]=100
)

# SVG dimensions
svg_width=40
svg_height=30
svg_margin=1

main() {
	date=$(date '+%s%3N')

	declare -A values=()
	declare -a values_pcent=()

	if [[ -n "$1" && -f "$1" ]]; then
		source "$1"
	fi

	data_load

	for i in "${bars[@]}"; do
		"get_${i}"
	done

	data_save
	create_svg
	#write_history

	echo -e "<img>/tmp/genmon-barchart.svg</img><tool><tt>${tooltip}</tt></tool>"
}

get_num_warn() {
	# In this function, the process of adding data is described.

	# In this case, we need to check whether the script is run with Superuser privileges.
	if [[ "$EUID" -ne 0 ]]; then
		tooltip+="<b>   num_warn</b>: N/A\n\n"
		return
	fi

	# 1: Retrieve the raw value of whatever data we will be adding.
	num_warn=$(journalctl --priority=warning --since -5min | wc -l)

	# 2: Push the raw value into the "values" array.
	values+=([num_warn]="$num_warn")

	# 3: Ensure that a maximum value exists in the "max_values" array declared above.

	# 4a: Get the raw values (rough) percentage of the maximum value
	num_warn_pcent=$((100*${values[num_warn]}/${values_max[num_warn]}))
	
	# 4b: If more precision is required, we could use the get_pcent() function
	#num_warn_pcent=$(get_pcent "${values[num_warn]}" "${values_max[num_warn]}")

	# 5: Push the percetage into the "values_pcent" array.
	values_pcent+=("$num_warn_pcent")

	# 6: Finally, append everything to the tooltip.
	tooltip+="<b>   num_warn</b>: ${values[num_warn]}/${values_max[num_warn]} (${num_warn_pcent}%)\n\n"
}

get_num_users() {
	values+=([num_users]=$(who | wc -l))

	num_users_pcent=$((100*${values[num_users]}/${values_max[num_users]}))
	values_pcent+=("$num_users_pcent")

	tooltip+="<b>  num_users</b>: ${values[num_users]}/${values_max[num_users]} (${num_users_pcent}%)\n"
}

get_num_procs() {
	values+=([num_procs]=$(find /proc/ -maxdepth 1 -type d -name "[1-9]*" | wc -l))

	num_procs_pcent=$((100*${values[num_procs]}/${values_max[num_procs]}))
	values_pcent+=("$num_procs_pcent")

	tooltip+="<b>  num_procs</b>: ${values[num_procs]}/${values_max[num_procs]} (${num_procs_pcent}%)\n\n"
}

get_cpu_load() {
	read -r cpu_freq cpu_freq_pcent cpu_load cpu_load_pcent < <(awk \
		-v cpu_freq_max=${values_max[cpu_freq]} \
		-v cpu_load=$(cut -d' ' -f1 < /proc/loadavg) \
		-v cpu_load_max=${values_max[cpu_load]} '/^cpu MHz/ {
			num_cores++
			mhz_sum+=$4
		} END {
			cpu_freq=mhz_sum/num_cores
			cpu_freq_pcent = (cpu_load_max>0) ? cpu_freq/cpu_freq_max*100 : 0
			cpu_load_pcent = (cpu_load_max>0) ? cpu_load/cpu_load_max*100 : 0
	
			printf "%d %d %.2f %d", cpu_freq, cpu_freq_pcent, cpu_load, cpu_load_pcent
		}' /proc/cpuinfo)

	values+=([cpu_freq]="$cpu_freq" [cpu_load]="$cpu_load")
	values_pcent+=("$cpu_freq_pcent" "$cpu_load_pcent")

	tooltip+="<b>   cpu_freq</b>: ${values[cpu_freq]}/${values_max[cpu_freq]} MHz (${cpu_freq_pcent}%)\n"
	tooltip+="<b>   cpu_load</b>: ${values[cpu_load]}/${values_max[cpu_load]} (${cpu_load_pcent}%)\n\n"
}

get_mem_usage() {
	read -r mem_total_gb mem_usage_gb mem_usage_pcent < <(free --mega -t | \
		awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')

	values+=([mem_usage_gb]="$mem_usage_gb")

	values_pcent+=("$mem_usage_pcent")

	tooltip+="<b>  mem_usage</b>: ${values[mem_usage_gb]}/$mem_total_gb GiB (${mem_usage_pcent}%)\n\n"
}

get_disk_usage() {
	read -r disk_size_gb disk_usage_gb disk_usage_pcent < <(df -BG --output=size,used,pcent "$disk_mount_point" | \
		awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')

	values+=([disk_usage_gb]="$disk_usage_gb")

	values_pcent+=("$disk_usage_pcent")

	tooltip+="<b> disk_usage</b>: ${values[disk_usage_gb]}/$disk_size_gb GiB (${disk_usage_pcent}%)\n\n"
}


get_net_rxtx() {
	read -r net_rx_mb net_rx_mbit_s net_rx_pcent net_tx_mb net_tx_mbit_s net_tx_pcent < <(awk \
		-v net_rx_mb_old=${values_old[net_rx_mb]} \
		-v net_tx_mb_old=${values_old[net_tx_mb]} \
		-v net_rx_mbit_s_max=${values_max[net_rx_mbit_s]} \
		-v net_tx_mbit_s_max=${values_max[net_tx_mbit_s]} \
		-v date=$date \
		-v date_old=${values_old[date]} 'BEGIN {
			time_delta=(date-date_old)/1000
		} {
			if (FILENAME ~ /rx/) {
				net_xx_mb_old = net_rx_mb_old
				net_xx_mbit_s_max = net_rx_mbit_s_max
			} else {
				net_xx_mb_old = net_tx_mb_old
				net_xx_mbit_s_max = net_tx_mbit_s_max
			}
		
			net_xx_mb=$1*8/10^6
			net_xx_mbit_s=(net_xx_mb-net_xx_mb_old)/time_delta
			net_xx_pcent = (net_xx_mbit_s_max>0) ? net_xx_mbit_s/net_xx_mbit_s_max*100 : 0
		
			printf "%f %.1f %d ", net_xx_mb, net_xx_mbit_s, net_xx_pcent
		}' /sys/class/net/$net_device/statistics/*x_bytes)

	values+=([net_rx_mb]="$net_rx_mb" [net_tx_mb]="$net_tx_mb")
	values+=([net_rx_mbit_s]="$net_rx_mbit_s" [net_tx_mbit_s]="$net_tx_mbit_s")

	values_pcent+=("$net_rx_pcent" "$net_tx_pcent")

	tooltip+="<b>     net_rx</b>: ${values[net_rx_mbit_s]}/${values_max[net_rx_mbit_s]} Mbps (${net_rx_pcent}%)\n"
	tooltip+="<b>     net_tx</b>: ${values[net_tx_mbit_s]}/${values_max[net_tx_mbit_s]} Mbps (${net_tx_pcent}%)\n\n"
}

get_net_skt() {
	mapfile -t < <(grep -hc '^\s\+[0-9]\+:\s' \
		"/proc/net/tcp" \
		"/proc/net/tcp6" \
		"/proc/net/udp" \
		"/proc/net/udp6") net_skt

	values+=([net_skt_tcp]=$((${net_skt[0]}+${net_skt[1]})))
	values+=([net_skt_udp]=$((${net_skt[2]}+${net_skt[3]})))

	net_skt_tcp_pcent=$((100*${values[net_skt_tcp]}/${values_max[net_skt_tcp]}))
	net_skt_udp_pcent=$((100*${values[net_skt_udp]}/${values_max[net_skt_udp]}))
	values_pcent+=("$net_skt_tcp_pcent" "$net_skt_udp_pcent")

	tooltip+="<b>net_skt_tcp</b>: ${values[net_skt_tcp]}/${values_max[net_skt_tcp]} (${net_skt_tcp_pcent}%)\n"
	tooltip+="<b>net_skt_udp</b>: ${values[net_skt_udp]}/${values_max[net_skt_udp]} (${net_skt_udp_pcent}%)\n\n"
}

get_disk_rw() {
	read -r disk_r_mb disk_r_mbyte_s disk_r_pcent disk_w_mb disk_w_mbyte_s disk_w_pcent < <(awk \
		-v disk_r_mb_old=${values_old[disk_r_mb]} \
		-v disk_w_mb_old=${values_old[disk_w_mb]} \
		-v disk_r_mbyte_s_max=${values_max[disk_r_mbyte_s]} \
		-v disk_w_mbyte_s_max=${values_max[disk_w_mbyte_s]} \
		-v date=$date \
		-v date_old=${values_old[date]} 'BEGIN {
			time_delta=(date-date_old)/1000
		} {
			disk_r_mb=$3*512/1024/1024
			disk_w_mb=$7*512/1024/1024
			
			disk_r_mbyte_s = (disk_r_mb>disk_r_mb_old) ? (disk_r_mb-disk_r_mb_old)/time_delta : 0
			disk_w_mbyte_s = (disk_w_mb>disk_w_mb_old) ? (disk_w_mb-disk_w_mb_old)/time_delta : 0
			
			disk_r_pcent = (disk_r_mbyte_s_max>0) ? disk_r_mbyte_s/disk_r_mbyte_s_max*100 : 0
			disk_w_pcent = (disk_w_mbyte_s_max>0) ? disk_w_mbyte_s/disk_w_mbyte_s_max*100 : 0
			
			printf "%f %.1f %d ", disk_r_mb, disk_r_mbyte_s, disk_r_pcent
			printf "%f %.1f %d ", disk_w_mb, disk_w_mbyte_s, disk_w_pcent
		}' "/sys/block/$disk_device/stat")

		values+=([disk_r_mb]="$disk_r_mb" [disk_w_mb]="$disk_w_mb")
		values+=([disk_r_mbyte_s]="$disk_r_mbyte_s" [disk_w_mbyte_s]="$disk_w_mbyte_s")

		values_pcent+=("$disk_r_pcent" "$disk_w_pcent")

		tooltip+="<b>     disk_r</b>: ${values[disk_r_mbyte_s]}/${values_max[disk_r_mbyte_s]} MBps (${disk_r_pcent}%)\n"
		tooltip+="<b>     disk_w</b>: ${values[disk_w_mbyte_s]}/${values_max[disk_w_mbyte_s]} MBps (${disk_w_pcent}%)"
}

get_power() {
	if [[ "$EUID" -ne 0 ]]; then
		tooltip+="<b>  cpu_power</b>: N/A\n"
		tooltip+="<b>  gpu_power</b>: N/A\n"
		return
	fi

	# https://github.com/djselbeck/rapl-read-ryzen
	values+=([cpu_w]=$(/usr/bin/rapl-read-ryzen | awk '/Core sum:/{gsub("W", ""); if ($3<1) {printf "1.0"} else {printf "%.1f", $3}}'))
	values+=([gpu_w]=$(awk '/(average GPU)/{printf "%.1f", $0}' /sys/kernel/debug/dri/0/amdgpu_pm_info))

	cpu_w_pcent=$((100*${values[cpu_w]%%.*}/${values_max[cpu_w]%%.*}))
	gpu_w_pcent=$((100*${values[gpu_w]%%.*}/${values_max[gpu_w]%%.*}))
	values_pcent+=("$cpu_w_pcent" "$gpu_w_pcent")

	tooltip+="\n\n<b>  cpu_power</b>: ${values[cpu_w]}/${values_max[cpu_w]} W (${cpu_w_pcent}%)\n"
	tooltip+="<b>  gpu_power</b>: ${values[gpu_w]}/${values_max[gpu_w]} W (${gpu_w_pcent}%)\n\n"
}

get_temp() {
	# Order may not be reliable
	read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
		"/sys/class/hwmon/hwmon3/temp1_input" \
		"/sys/class/hwmon/hwmon2/temp2_input" \
		"/sys/class/hwmon/hwmon0/temp1_input")

	values+=([cpu_temp]="$cpu_temp" [gpu_temp]="$gpu_temp" [ssd_temp]="$ssd_temp")

	cpu_temp_pcent=$((100*${values[cpu_temp]%%.*}/${values_max[cpu_temp]%%.*}))
	gpu_temp_pcent=$((100*${values[gpu_temp]%%.*}/${values_max[gpu_temp]%%.*}))
	ssd_temp_pcent=$((100*${values[ssd_temp]%%.*}/${values_max[ssd_temp]%%.*}))
	values_pcent+=("$cpu_temp_pcent" "$gpu_temp_pcent" "$ssd_temp_pcent")

	tooltip+="<b>   cpu_temp</b>: ${values[cpu_temp]}/${values_max[cpu_temp]} C (${cpu_temp_pcent}%)\n"
	tooltip+="<b>   gpu_temp</b>: ${values[gpu_temp]}/${values_max[gpu_temp]} C (${gpu_temp_pcent}%)\n"
	tooltip+="<b>   ssd_temp</b>: ${values[ssd_temp]}/${values_max[ssd_temp]} C (${ssd_temp_pcent}%)"
}

data_load() {
	source "$values_file" || declare -Ag values_old

	for i in "${!values_max[@]}"; do
		if [[ "${values_max[$i]}" == "auto" ]]; then
			values_max[$i]="${values_old[$i]}"
		fi

		if [[ -z "${values_old[$i]}" ]]; then
			values_max[$i]=-1
		fi
	done
}

data_save() {
	for i in "${!values[@]}"; do
		if [[ "${values[$i]%%.*}" -lt "${values_max[$i]%%.*}" ]]; then
			values[$i]="${values_max[$i]}"
		fi
	done

	values+=([date]="${date}")

	declare -Ap values | sed 's/ -A values/ -Ag values_old/' > "$values_file"
}

get_pcent() {
	awk -v value="$1" -v total="$2" 'BEGIN {
		if (value>0 && total>0) {printf "%d", value/total*100} else {print 0}}'
}

get_rate() {
	awk -v new="$1" -v old="$2" -v date="$3" -v date_old="$4" 'BEGIN {
		if (date>date_old) {printf "%.1f", (new-old)/((date-date_old)/1000)} else {print 0}}'
}

draw_elements() {
	local svg_width=$(((svg_width-svg_margin)/${#values_pcent[@]}-svg_margin))

	for ((i=0; i<${#values_pcent[@]}; i++)); do
		local x=$(((svg_width+svg_margin)*i))
		local svg_height=$((((${values_pcent[$i]%.*}+5)/10)*10))

		bars+="<rect class='bar bar--$i' width='$svg_width' height='${svg_height}%' x='$x' y='0' />"
	done

	for i in {0..100..10}; do
		lines+="<line class='line' x1='0' y1='${i}%' x2='100%' y2='${i}%' />"
	done
}

create_svg() {
	draw_elements

	cat <<- SVG > /tmp/genmon-barchart.svg
	<svg version="1.1"
		width="$svg_width"
		height="$svg_height"
		xmlns="http://www.w3.org/2000/svg">

		<style>
			.container { fill: #000; }
			.bar:nth-of-type(14n+1) { fill: #A93226; }
			.bar:nth-of-type(14n+2) { fill: #CB4335; }
			.bar:nth-of-type(14n+3) { fill: #884EA0; }
			.bar:nth-of-type(14n+4) { fill: #7D3C98; }
			.bar:nth-of-type(14n+5) { fill: #2471A3; }
			.bar:nth-of-type(14n+6) { fill: #2E86C1; }
			.bar:nth-of-type(14n+7) { fill: #17A589; }
			.bar:nth-of-type(14n+8) { fill: #138D75; }
			.bar:nth-of-type(14n+9) { fill: #229954; }
			.bar:nth-of-type(14n+10) { fill: #28B463; }
			.bar:nth-of-type(14n+11) { fill: #D4AC0D; }
			.bar:nth-of-type(14n+12) { fill: #D68910; }
			.bar:nth-of-type(14n+13) { fill: #CA6F1E; }
			.bar:nth-of-type(14n+14) { fill: #BA4A00; }
			.line { stroke: #000; stroke-width: $svg_margin }
		</style>
	
		<rect class="container" width="$svg_width" height="$svg_height" />
		<svg width="$((svg_width-svg_margin*2))" height="$((svg_height-svg_margin*2))"
			x="$svg_margin" y="$svg_margin" transform="scale(1,-1) translate(0,-$svg_height)">
			<g>$bars</g>
			<g>$lines</g>
		</svg>
	</svg>
	SVG
}

write_history() {
	values_joined=$(printf ",%s" "${values[@]}")
	echo "${date::-3}${values_joined}" >> "/tmp/genmon-barchart-history.txt"
}

main "$@"

exit 0
