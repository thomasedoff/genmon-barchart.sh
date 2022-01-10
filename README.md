# svgstat.sh
Bash script that displays system information in an SVG graph.

![svgstat sh](https://user-images.githubusercontent.com/51061686/148831778-1a0d0aa5-91c3-4c0d-9dba-2c63dc522b0a.gif)

## Description
svgstat.sh is a simple script that gathers system information and generates an SVG graph.

It can be used with [xfce4-genmon-plugin](https://gitlab.xfce.org/panel-plugins/xfce4-genmon-plugin) to show the graph on an XFCE panel.
It is not meant to replace [Task Manager](https://docs.xfce.org/apps/xfce4-taskmanager/start) or the like. But it can provide at-a-glance information without having to add multiple monitors/commands.

## How to use
1. Edit ``General settings`` and ``SVG settings`` in the script. 
2. Add a Generic Monitor (xfce-genmon-plugin) to a panel and set the sript as the command.

## Customization
Colors can be edited in the CSS ``<style>``-tag witin the script.

## Caveats
The paths to temperature sources need to be edited in the ``get_temps()`` function.
