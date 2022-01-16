# genmon-barchart.sh
 An XFCE GenMon script that displays customizable system information in a compact bar chart.

![genmon-barchart](https://user-images.githubusercontent.com/51061686/149675374-45d7606a-7d44-4fc5-aa24-e8ec70bf4e45.gif)

## Description
genmon-barchart.sh is a script that gathers system information and creates an SVG bar chart to be be displayed on an XFCE panel by [xfce4-genmon-plugin](https://gitlab.xfce.org/panel-plugins/xfce4-genmon-plugin) (GenMon).

The script can be an alternative/addition to [CPUGraph](https://docs.xfce.org/panel-plugins/xfce4-cpugraph-plugin/start), [Sensors](https://docs.xfce.org/panel-plugins/xfce4-sensors-plugin/start), [DiskPerf](https://docs.xfce.org/panel-plugins/xfce4-diskperf-plugin/start), etc. But primary idea is to provide a compact overview of system activity.

By hovering the bars, additional information will be displayed.

## How to use
1. Edit the ``General settings``, ``Functions``, ``Max values`` and ``SVG dimensions`` sections in the script.
2. Add a General Monitor (xfce4-genmon-plugin) to a panel and set the script as the command.
3. Optionally configure the label and period to your liking.
4. Certain functions (currently ``get_power``) require Superuser privileges to retrieve the values. See below.

## Considerations
Most functions should be portable, but ``get_power`` and ``get_temp`` are system-specific. Please consider these functions **examples** rather than something that will work for you out of the box.

One way to allow genmon to run the script with Superuser privileges without a password is to configure ``/etc/sudoers`` as such:
```
NAME_OF_USER ALL=NOPASSWD: /usr/local/bin/genmon-barchart.sh
```
## Adding data to the chart
There is a function called ``example`` that describes this process, and may be used as a template for adding data to the chart. 

## Customization
- Depending on how many bars you include in the chart, you may have to adjust ``svg_width`` to fit all bars without unnecessary margins.
- If you are unsure of what maximum values to set, set them to ``auto`` and stress your system in order to record some approximate values.
- Colors can be edited in the CSS ``<style>``-tag within the script.
- Hint: By inserting hard-coded 0's into the ``values_pcent`` indexed array, it is possible to create gaps between groups of bars.

## Ideas/todo
- Read up on and potentially implement further use of [Pango Text Attributes](https://docs.gtk.org/Pango/pango_markup.html) in the tooltip.
- Make use of and allow easy customization of GenMons ``<click>`` feature.
- To not waste use of the pretty rainbow colors, perhaps do not increment colors when value is 0.
