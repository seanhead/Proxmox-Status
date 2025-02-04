#!/bin/bash

arcstats_file="/proc/spl/kstat/zfs/arcstats"
zilstats_file="/proc/spl/kstat/zfs/zil"

numfmt_bytes="numfmt --to=iec-i --suffix=B --format=%0.1f"

# add a space between the number and unit, e.g. 53GiB -> 53 GiB
iec_space_regexp="s/([0-9])([A-Z])/\1 \2/"


# get current and max ARC size
arc_size=$(cat "$arcstats_file" | awk '{ if ($1 == "size") print $3 }' | $numfmt_bytes | sed -E "$iec_space_regexp")
max_arc_size=$(cat "$arcstats_file" | awk '{ if ($1 == "c_max") print $3 }' | $numfmt_bytes | sed -E "$iec_space_regexp")

# calculate ARC hit ratio
hits=$(cat "$arcstats_file" | awk '{ if ($1 == "hits") print $3 }')
misses=$(cat "$arcstats_file" | awk '{ if ($1 == "misses") print $3 }')
total_arc_requests=$(( hits + misses ))
hit_ratio=$( bc <<< "scale=2; $hits * 100 / $total_arc_requests" )


# get the ARC section of the arc_summary command to get ZFS cache utilization info
arc_summary=$(/sbin/arc_summary -s arc)

mfu_size=$(echo "$arc_summary" | grep "Most Frequently Used (MFU) cache size" | awk '{ print $9 " " $10 }')
mru_size=$(echo "$arc_summary" | grep "Most Recently Used (MRU) cache size" | awk '{ print $9 " " $10 }')
metadata_cache_size=$(echo "$arc_summary" | grep "Metadata cache size (current)" | awk '{ print $7 " " $8 }' )
dnode_cache_size=$(echo "$arc_summary" | grep "Dnode cache size (current)" | awk '{ print $7 " " $8 }')

arc_utilization=$(
	printf "|ARC Size:|%s|%s (Max)\n" "$arc_size" "$max_arc_size"
	printf "|Hit Ratio:|$hit_ratio %%\n"
	printf "|MFU Size:|$mfu_size \n"
	printf "|MRU Size:|$mru_size \n"
	printf "|Metadata Cache Size:|$metadata_cache_size \n"
	printf "|Dnode Cache Size:|$dnode_cache_size \n"
)


# get the size and number of transactions written to the SLOG pool
slog_transaction_size=$(/sbin/arc_summary -s zil | grep "Transactions to SLOG storage pool" | awk '{ print $6 " " $7 "|" $8 " " $9 }')

slog_transaction_count=$(cat "$zilstats_file" | awk '$0 ~ /zil_itx_metaslab_slog_count/ { print $3 }')
slog_transaction_bytes=$(cat "$zilstats_file" | awk '$0 ~ /zil_itx_metaslab_slog_bytes/ { print $3 }')

# calculate transactions and bytes per second
uptime=$(cat /proc/uptime | awk '{ print $1 }')
slog_tps=$( bc <<< "scale=1; $slog_transaction_count / $uptime"  )
slog_bytes_per_sec=$( bc <<< "scale=2; $slog_transaction_bytes / $uptime" | $numfmt_bytes | sed -E "$iec_space_regexp" )

zil_utilization=$(
    printf "|ZIL SLOG Transactions:|$slog_transaction_size \n"
    printf "|ZIL SLOG TPS:|$slog_tps itx/sec \n"
    printf "|ZIL SLOG Writes:|$slog_bytes_per_sec/sec \n"
)


# get the size and hit ratio of the L2ARC
l2arc_size=$(/sbin/arc_summary -s l2arc | awk '$0 ~ /L2ARC size \(adaptive\)/ { print $4 " " $5 }')
l2arc_size_compressed=$(/sbin/arc_summary -s l2arc | awk '$0 ~ /Compressed/ { print $4 " " $5 "|" $2 " " $3 }')
l2arc_hit_ratio=$(/sbin/arc_summary -s l2arc | awk '$0 ~ /Hit ratio/ { print $3 " " $4 "|" $5 }')

l2arc_stats=$(
	echo "|L2ARC Size:|$l2arc_size"
	echo "|L2ARC Size (compressed):|$l2arc_size_compressed"
	echo "|L2ARC Hit Ratio:|$l2arc_hit_ratio"
)


# print final output in table format
column -t -s '|' <<< $(
	printf "ARC Stats:\n%s\n" "$arc_utilization"
	printf "ZIL Stats:\n%s\n" "$zil_utilization"
	printf "L2ARC Stats:\n%s\n" "$l2arc_stats"
)
