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

# Bars to be included in the chart
declare -a values_order=(
#	"num_warn"
	"num_users"
	"num_procs"
	"<blank>"
	"cpu_freq"
	"cpu_load"
	"<blank>"
	"mem_usage_gb"
	"disk_usage_gb"
	"<blank>"
	"net_rx_mbit_s"
	"net_tx_mbit_s"
	"<blank>"
	"net_skt_tcp"
	"net_skt_udp"
	"<blank>"
	"disk_r_mbyte_s"
	"disk_w_mbyte_s"
#	"<blank>"
#	"cpu_w"
#	"gpu_w"
#	"<blank>"
#	"cpu_temp"
#	"gpu_temp"
#	"ssd_temp"
)


# Max values for bars whose function does not determine a maximum
# If set to auto, the percentages will be based on the highest value recorded.
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
svg_width=37
svg_height=30
svg_margin=1
svg_include_blanks="false"

main() {
	declare -A values=()
	declare -a values_titles=()
	declare -a values_pcent=()
	
	# Current date in milliseconds
	date=$(date '+%s%3N')

	# Load settings from external file
	[[ -n "$1" && -f "$1" ]] && source "$1"

	# Load previous values in order to set max and calculate rates
	data_load "$values_file"

	# Execute necessary functions to get data for requested bars
	for i in "${values_order[@]}"; do
		local pcent="0"
		local unit=""
		local tmp=""
		
		case $i in
			"num_warn") 
				num_warn
			;;
			"num_users")
				num_users
			;;
			"num_procs")
				num_procs
			;;
			"cpu_freq" | "cpu_load")
				# Since cpu_load() return values for both bars, only execute the function once
				[[ -v "values[$i]" ]] || cpu_load
			;;
			"mem_usage_gb")
				mem_usage && unit="GB "
			;;
			"disk_usage_gb")
				disk_usage "$disk_mount_point" && unit="GB "
			;;
			"net_rx_mbit_s" | "net_tx_mbit_s")
				[[ -v "values[$i]" ]] || net_rxtx "$net_device" && unit="Mbps "
			;;
			"net_skt_tcp" | "net_skt_udp")
				[[ -v "values[$i]" ]] || net_skt
			;;
			"disk_r_mbyte_s" | "disk_w_mbyte_s")
				[[ -v "values[$i]" ]] || disk_rw "$disk_device" && unit="MBbps "
			;;
			"cpu_w" | "gpu_w")
				[[ -v "values[$i]" ]] || power && unit="W "
			;;
			"cpu_temp" | "gpu_temp" | "ssd_temp")
				[[ -v "values[$i]" ]] || temp && unit="C "
			;;
		esac
		
		# Add a newline to the tooltip and, optionally, a gap to the chart
		if [[ "$i" == "<blank>" ]]; then
			printf -v tmp "%s" "\n"
			[[ "$svg_include_blanks" == "true" ]] && values_pcent+=(0)
			tooltip+=$tmp
			continue
		fi
		
		if [[ -n "${values[$i]}" && -n "${values_max[$i]}" && -v "values[${i}_pcent]" ]]; then
			# Function returned a percentage, so simply use that value
			pcent="${values[${i}_pcent]}"
		elif [[ -n "${values[$i]}" && "${values_max[$i]}" -eq 0 ]]; then
			# Function returned a zero max value, so avoid div/0
			pcent=0
		elif [[ -n "${values[$i]}" && -n "${values_max[$i]}" ]]; then
			# Function did not return a percentage, so we need to calculate it
			pcent=$((100*${values[$i]%%.*}/${values_max[$i]%%.*}))
			
			# If more precision is required, use awk instead 
			#pcent=$(awk -v value="${values[$i]}" -v total="${values_max[$i]}" 'BEGIN {printf "%d", value/total*100}')
		else
			# Function did not return the necessary values
			printf -v tmp "<b>%14s</b>: %s\n" "$i" "N/A"
			tooltip+=$tmp
			continue
		fi

		# Prepare values needed by create_svg()
		values_titles+=("$i")
		values_pcent+=("$pcent")
		
		# Create tooltip
		printf -v tmp "<b>%14s</b>: %g/%g %s(%d%%)\n" "$i" "${values[$i]}" "${values_max[$i]}" "$unit" "$pcent"
		tooltip+=$tmp
	done

	# Create chart with bars based on percentages
	create_svg
	
	# Save data with potential new max values
	data_save "$values_file"

	# Output for GenMon
	echo -e "<img>/tmp/genmon-barchart.svg</img><tool><tt>$tooltip</tt></tool>"
}

num_warn() {
	[[ "$EUID" -ne 0 ]] && return
	values+=([num_warn]=$(journalctl --priority=warning --since -5min | wc -l))
}

num_users() {
	values+=([num_users]=$(who | wc -l))
}

num_procs() {
	values+=([num_procs]=$(find /proc/ -maxdepth 1 -type d -name "[1-9]*" | wc -l))
}

cpu_load() {
	read -r -d '' awk_cpu_load <<- 'EOF'
		/^cpu MHz/ {
			num_cores++
			mhz_sum+=$4
		} END {
			cpu_freq=mhz_sum/num_cores
			cpu_freq_pcent = (cpu_load_max>0) ? cpu_freq/cpu_freq_max*100 : 0
			cpu_load_pcent = (cpu_load_max>0) ? cpu_load/cpu_load_max*100 : 0

			printf "%d %d %.2f %d", cpu_freq, cpu_freq_pcent, cpu_load, cpu_load_pcent
		}
	EOF
		
	read -r cpu_freq cpu_freq_pcent cpu_load cpu_load_pcent < <(awk \
		-v cpu_freq_max="${values_max[cpu_freq]}" \
		-v cpu_load="$(cut -d' ' -f1 < /proc/loadavg)" \
		-v cpu_load_max="${values_max[cpu_load]}" "$awk_cpu_load" /proc/cpuinfo)

	values+=([cpu_freq]="$cpu_freq" [cpu_freq_pcent]="$cpu_freq_pcent")
	values+=([cpu_load]="$cpu_load" [cpu_load_pcent]="$cpu_load_pcent")
}

mem_usage() {
	read -r mem_total_gb mem_usage_gb mem_usage_gb_pcent < <(free --mega -t | \
		awk 'NR==2{printf "%.1f %.1f %d", $2/1024, $3/1024, $3/$2*100}')

	values+=([mem_usage_gb]="$mem_usage_gb" [mem_usage_gb_pcent]="$mem_usage_gb_pcent")
	values_max+=([mem_usage_gb]="$mem_total_gb")
}

disk_usage() {
	read -r disk_size_gb disk_usage_gb disk_usage_gb_pcent < <(df -BG --output=size,used,pcent "$1" | \
		awk 'NR==2{gsub("(G|%)", ""); print $1, $2, $3}')

	values+=([disk_usage_gb]="$disk_usage_gb" [disk_usage_gb_pcent]="$disk_usage_gb_pcent")
	values_max+=([disk_usage_gb]="$disk_size_gb")
}

net_rxtx() {
	read -r -d '' awk_net_rxtx <<- 'EOF'
		BEGIN {
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
			net_xx_mbit_s_pcent = (net_xx_mbit_s_max>0) ? net_xx_mbit_s/net_xx_mbit_s_max*100 : 0

			printf "%f %.1f %d ", net_xx_mb, net_xx_mbit_s, net_xx_mbit_s_pcent
		}
	EOF
		
	read -r net_rx_mb net_rx_mbit_s net_rx_mbit_s_pcent net_tx_mb net_tx_mbit_s net_tx_mbit_s_pcent < <(awk \
		-v net_rx_mb_old="${values_old[net_rx_mb]}" \
		-v net_tx_mb_old="${values_old[net_tx_mb]}" \
		-v net_rx_mbit_s_max="${values_max[net_rx_mbit_s]}" \
		-v net_tx_mbit_s_max="${values_max[net_tx_mbit_s]}" \
		-v date="$date" \
		-v date_old="${values_old[date]}" \
		"$awk_net_rxtx" /sys/class/net/$net_device/statistics/*x_bytes)

	values+=([net_rx_mb]="$net_rx_mb" [net_tx_mb]="$net_tx_mb")
	values+=([net_rx_mbit_s]="$net_rx_mbit_s" [net_tx_mbit_s]="$net_tx_mbit_s")
	values+=([net_rx_mbit_s_pcent]="$net_rx_mbit_s_pcent" [net_tx_mbit_s_pcent]="$net_tx_mbit_s_pcent")
}

net_skt() {
	mapfile -t < <(grep -hc '^\s\+[0-9]\+:\s' \
		"/proc/net/tcp" \
		"/proc/net/tcp6" \
		"/proc/net/udp" \
		"/proc/net/udp6") net_skt

	values+=([net_skt_tcp]=$((net_skt[0]+net_skt[1])))
	values+=([net_skt_udp]=$((net_skt[2]+net_skt[3])))
}

disk_rw() {
	read -r -d '' awk_disk_rw <<- 'EOF'
		BEGIN {
			time_delta=(date-date_old)/1000
		} {
			disk_r_mb=$3*512/1024/1024
			disk_w_mb=$7*512/1024/1024

			disk_r_mbyte_s = (disk_r_mb>disk_r_mb_old) ? (disk_r_mb-disk_r_mb_old)/time_delta : 0
			disk_w_mbyte_s = (disk_w_mb>disk_w_mb_old) ? (disk_w_mb-disk_w_mb_old)/time_delta : 0

			disk_r_mbyte_s_pcent = (disk_r_mbyte_s_max>0) ? disk_r_mbyte_s/disk_r_mbyte_s_max*100 : 0
			disk_w_mbyte_s_pcent = (disk_w_mbyte_s_max>0) ? disk_w_mbyte_s/disk_w_mbyte_s_max*100 : 0

			printf "%f %.1f %d ", disk_r_mb, disk_r_mbyte_s, disk_r_mbyte_s_pcent
			printf "%f %.1f %d ", disk_w_mb, disk_w_mbyte_s, disk_w_mbyte_s_pcent
		}
	EOF
	
	read -r disk_r_mb disk_r_mbyte_s disk_r_mbyte_s_pcent disk_w_mb disk_w_mbyte_s disk_w_mbyte_s_pcent < <(awk \
		-v disk_r_mb_old="${values_old[disk_r_mb]}" \
		-v disk_w_mb_old="${values_old[disk_w_mb]}" \
		-v disk_r_mbyte_s_max="${values_max[disk_r_mbyte_s]}" \
		-v disk_w_mbyte_s_max="${values_max[disk_w_mbyte_s]}" \
		-v date="$date" \
		-v date_old="${values_old[date]}" "$awk_disk_rw" "/sys/block/$1/stat")

		values+=([disk_r_mb]="$disk_r_mb" [disk_w_mb]="$disk_w_mb")
		values+=([disk_r_mbyte_s]="$disk_r_mbyte_s" [disk_w_mbyte_s]="$disk_w_mbyte_s")
		values+=([disk_r_mbyte_s_pcent]="$disk_r_mbyte_s_pcent" [disk_w_mbyte_s_pcent]="$disk_w_mbyte_s_pcent")
}

power() {
	[[ "$EUID" -ne 0 ]] && return
	# https://github.com/djselbeck/rapl-read-ryzen
	values+=([cpu_w]=$(/usr/bin/rapl-read-ryzen | awk '/Core sum:/{gsub("W", ""); printf "%.1f", $3}'))
	values+=([gpu_w]=$(awk '/(average GPU)/{printf "%.1f", $0}' /sys/kernel/debug/dri/0/amdgpu_pm_info))
}

temp() {
	# Order may not be reliable
	read -r cpu_temp gpu_temp ssd_temp < <(awk '{printf "%.1f ", $1/1000}' \
		"/sys/class/hwmon/hwmon3/temp1_input" \
		"/sys/class/hwmon/hwmon2/temp2_input" \
		"/sys/class/hwmon/hwmon0/temp1_input")

	values+=([cpu_temp]="$cpu_temp" [gpu_temp]="$gpu_temp" [ssd_temp]="$ssd_temp")
}

data_load() {
	source "$1" || declare -Ag values_old

	for i in "${!values_max[@]}"; do
		if [[ "${values_max[$i]}" == "auto" ]]; then
			values_max[$i]="${values_old[$i]}"
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

	declare -Ap values | sed 's/ -A values/ -Ag values_old/' > "$1"
}

draw_elements() {
	local svg_width=$(((svg_width-svg_margin)/${#values_pcent[@]}-svg_margin))

	for ((i=0; i<${#values_pcent[@]}; i++)); do
		local x=$(((svg_width+svg_margin)*i))
		local svg_height=$((((${values_pcent[$i]%.*}+5)/10)*10))

		bars+="<rect class='bar bar--${values_titles[$i]}' width='$svg_width' height='${svg_height}%' x='$x' y='0' />"
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
			.line { stroke: #000; stroke-width: $svg_margin }
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
			/*
				The attributes above will loop rainbow colors forever
				To set specific colors for a bar, its title can be referenced:
				.bar--num_users { fill: #fff !important; }
			*/
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

main "$@"

exit 0
