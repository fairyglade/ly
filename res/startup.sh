#!/bin/sh
# This file is executed when starting Ly (before the TTY is taken control of)
# Custom startup code can be placed in this file or the start_cmd var can be pointed to a different file


# Uncomment the example below for an example of changing the default TTY colors to an alternitive palette on linux
# Colors are in red/green/blue hex (the current colors are a brighter palette than default)
#
#if [ "$TERM" = "linux" ]; then
#	declare -a colors=(
#		[0]="232323"  # black
#		[1]="D75F5F"  # dark red
#		[2]="87AF5F"  # dark green
#		[3]="D7AF87"  # dark yellow
#		[4]="8787AF"  # dark blue
#		[5]="BD53A5"  # dark magenta
#		[6]="5FAFAF"  # dark cyan
#		[7]="E5E5E5"  # light gray
#		[8]="2B2B2B"  # dark gray
#		[9]="E33636"  # red
#		[10]="98E34D" # green
#		[11]="FFD75F" # yellow
#		[12]="7373C9" # blue
#		[13]="D633B2" # magenta
#		[14]="44C9C9" # cyan
#		[15]="FFFFFF" # white
#	)
#	
#	control_palette_str="\e]P"
#	
#	for i in ${!colors[@]}
#	do
#		echo -en "${control_palette_str}$( printf "%x" ${i} )${colors[i]}"
#	done
#
#	clear # for fixing background artifacting after changing color
#fi

