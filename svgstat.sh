#!/bin/bash

# svgstat.sh - Bash/genmon script that displays system information in an SVG graph.
# The script can be used with xfce4-genmon-plugin to show a graph onto the panel.
#
# https://github.com/thomasedoff/svgstat.sh

# General settings
disk_mount_point="/home/"
disk_device="nvme1n1"
net_device="enp6s0"
values_file="/tmp/svgstat-values"

# Functions
declare -a keys=(
	cpu_load
	mem_usage
	disk_usage
	net_rxtx
	disk_rw
	power
	temp
	#example
)

# Max values - If set to auto, the percentages will be based on the highest value recorded.
declare -A values_max=(
	[net_rx_mbps]=50
	[net_tx_mbps]=50
	[disk_r_mbps]="auto"
	[disk_w_mbps]="auto"
	[cpu_w]="auto"
	[gpu_w]="auto"
	[cpu_temp]=100
	[gpu_temp]=100
	[ssd_temp]=100
	#[example]=1000
)

# SVG dimensions
svg_width=37
svg_height=30
svg_margin=1

get_cpu_load() {
	values+=([cpu_load]=$(cut -d' ' -f1 < /proc/loadavg))

	cpu_load_pcent=$(get_pcent "${values[cpu_load]}" "$(grep -c ^processor /proc/cpuinfo)")
	values_pcent+=("$cpu_load_pcent")

	tooltip+="cpu_load: ${values[cpu_load]} (${cpu_load_pcent}%)\n"
}

get_mem_usage() {
	read -r mem_total_gb mem_usage_gb mem_usage_pcent < <(free --mega -t | \
		awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')

	values+=([mem_usage_gb]="$mem_usage_gb")

	values_pcent+=("$mem_usage_pcent")

	tooltip+="mem_usage: ${values[mem_usage_gb]}/$mem_total_gb GiB (${mem_usage_pcent}%)\n"
}

get_disk_usage() {
	read -r disk_size_gb disk_usage_gb disk_usage_pcent < <(df -BG --output=size,used,pcent "$disk_mount_point" | \
		awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')

	values+=([disk_usage_gb]="$disk_usage_gb")

	values_pcent+=("$disk_usage_pcent")

	tooltip+="disk_usage: ${values[disk_usage_gb]}/$disk_size_gb GiB (${disk_usage_pcent}%)\n\n"
}


get_net_rxtx() {
	read -r net_rx_mb net_tx_mb < <(awk '{printf "%f ", $1*8/10^6}' \
		 "/sys/class/net/$net_device/statistics/rx_bytes" \
		 "/sys/class/net/$net_device/statistics/tx_bytes")

	values+=([net_rx_mb]="$net_rx_mb" [net_tx_mb]="$net_tx_mb" )
	values+=([net_rx_mbps]=$(get_rate "$net_rx_mb" "${values_old[net_rx_mb]}" "$date" "${values_old[date]}"))
	values+=([net_tx_mbps]=$(get_rate "$net_tx_mb" "${values_old[net_tx_mb]}" "$date" "${values_old[date]}"))

	net_rx_pcent=$(get_pcent "${values[net_rx_mbps]}" "${values_max[net_rx_mbps]}")
	net_tx_pcent=$(get_pcent "${values[net_tx_mbps]}" "${values_max[net_tx_mbps]}")
	values_pcent+=("$net_rx_pcent" "$net_tx_pcent")

	tooltip+="net_rx: ${values[net_rx_mbps]}/${values_max[net_rx_mbps]} Mbps (${net_rx_pcent}%)\n"
	tooltip+="net_tx: ${values[net_tx_mbps]}/${values_max[net_tx_mbps]} Mbps (${net_tx_pcent}%)\n\n"
}

get_disk_rw() {
	read -r disk_r_mb disk_w_mb < <(awk '{printf "%d %d", $3*512/1024/1024, $7*512/1024/1024 }' \
		"/sys/block/$disk_device/stat")

	values+=([disk_r_mb]="$disk_r_mb" [disk_w_mb]="$disk_w_mb" )
	values+=([disk_r_mbps]=$(get_rate "$disk_r_mb" "${values_old[disk_r_mb]}" "$date" "${values_old[date]}"))
	values+=([disk_w_mbps]=$(get_rate "$disk_w_mb" "${values_old[disk_w_mb]}" "$date" "${values_old[date]}"))

	disk_r_pcent=$(get_pcent "${values[disk_r_mbps]}" "${values_max[disk_r_mbps]}")
	disk_w_pcent=$(get_pcent "${values[disk_w_mbps]}" "${values_max[disk_w_mbps]}")
	values_pcent+=("$disk_r_pcent" "$disk_w_pcent")

	tooltip+="disk_r: ${values[disk_r_mbps]}/${values_max[disk_r_mbps]} MBps (${disk_r_pcent}%)\n"
	tooltip+="disk_w: ${values[disk_w_mbps]}/${values_max[disk_w_mbps]} MBps (${disk_w_pcent}%)\n\n"

}

get_power() {
	# Superuser privileges are required to read these values.
	# https://github.com/djselbeck/rapl-read-ryzen
	if [[ "$EUID" -eq 0 ]]; then
		values+=([cpu_w]=$(/usr/bin/rapl-read-ryzen | awk '/Core sum:/{gsub("W", ""); printf "%.1f", $3}'))
		values+=([gpu_w]=$(awk '/(average GPU)/{printf "%.1f", $0}' /sys/kernel/debug/dri/0/amdgpu_pm_info))

		cpu_w_pcent=$(get_pcent "${values[cpu_w]}" "${values_old[cpu_w]}")
		gpu_w_pcent=$(get_pcent "${values[gpu_w]}" "${values_old[gpu_w]}")
		values_pcent+=("$cpu_w_pcent" "$gpu_w_pcent")
		
		tooltip+="cpu_power: ${values[cpu_w]}/${values_max[cpu_w]} W (${cpu_w_pcent}%)\n"
		tooltip+="gpu_power: ${values[gpu_w]}/${values_max[gpu_w]} W (${gpu_w_pcent}%)\n\n"
	fi
	
}

get_temp() {
	# Order may not be reliable
	read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
		"/sys/class/hwmon/hwmon3/temp1_input" \
		"/sys/class/hwmon/hwmon2/temp2_input" \
		"/sys/class/hwmon/hwmon0/temp1_input")

	values+=([cpu_temp]="$cpu_temp" [gpu_temp]="$gpu_temp" [ssd_temp]="$ssd_temp")

	cpu_temp_pcent=$(get_pcent "${values[cpu_temp]}" "${values_max[cpu_temp]}")
	gpu_temp_pcent=$(get_pcent "${values[gpu_temp]}" "${values_max[gpu_temp]}")
	ssd_temp_pcent=$(get_pcent "${values[ssd_temp]}" "${values_max[ssd_temp]}")
	values_pcent+=("$cpu_temp_pcent" "$gpu_temp_pcent" "$ssd_temp_pcent")

	tooltip+="cpu_temp: ${values[cpu_temp]}/${values_max[cpu_temp]} C (${cpu_temp_pcent}%)\n"
	tooltip+="gpu_temp: ${values[gpu_temp]}/${values_max[gpu_temp]} C (${gpu_temp_pcent}%)\n"
	tooltip+="ssd_temp: ${values[ssd_temp]}/${values_max[ssd_temp]} C (${ssd_temp_pcent}%)"

}

get_example() {
	# This function is an example on how additional information can be added to the graph.
	
	# First, get the raw value of whatever data should be retrieved.
	# In this example, it's the number of running processes on the system.
	# Normally, all instances of "example" would be "num_procs".
	example=$(ps aux --no-heading | wc -l)

	# Since the bars height is calculated as a percentage, we need to set a maximum.
	# Preferably, this is set by adding the key "num_procs" and value to the "values_max" array.

	# To calculate percentages, we can use the get_pcent() function.
	example_pcent=$(get_pcent "$example" "${values_max[example]}")

	# Once we have a percentage, we can append this information to the (indexed) "values_pcent" array.
	# This will add a new bar to the SVG graph. Optionally, we can prepend a hard-coded "0" to create
	# a gap before the previous bars.
	example_pcent+=(0 "$example_pcent")

	# In order to save the maximum value seen and use "auto" setting, the raw value must be appended
	# To the (associative) "values" array.
	values+=([example]="$example")

	# Finally, add the information to the tooltip so that it appears when hovering the graph.
	tooltip+="\n\nexample $example/${values_max[example]} (${example_pcent}%)"

	# That's it!
}

data_load() {
	source "$values_file" || declare -Ag values_old

	for i in "${!values_max[@]}"; do
		if [[ "${values_max[$i]}" == "auto" ]]; then
			values_max[$i]=${values_old[$i]}
		fi

		if [[ -z "${values_old[$i]}" ]]; then
			values_max[$i]=0
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

write_history() {
	values_joined=$(printf ",%s" "${values[@]}")
	echo "${date::-3}${values_joined}" >> "/tmp/svgstat-history.txt"
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

	cat <<- SVG > /tmp/svgstat-graph.svg
	<svg version="1.1"
		width="$svg_width"
		height="$svg_height"
		xmlns="http://www.w3.org/2000/svg">

		<style>
			.container { fill: #000; }
			.bar { fill: #FFF; }
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

date=$(date '+%s%3N')

declare -A values=()
declare -a values_pcent=()

data_load
for i in "${keys[@]}"; do "get_${i}"; done
data_save
create_svg
#write_history

echo -e "<img>/tmp/svgstat-graph.svg</img><tool>${tooltip}</tool>"

exit 0
