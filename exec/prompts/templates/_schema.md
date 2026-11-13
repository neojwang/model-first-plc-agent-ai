GRAFCET JSON schema (the tuple of Equation (1) of the paper):

{
  "graphs": [ {"name": "G1", "steps": ["x0", "x1"], "initial": ["x0"]} ],
  "transitions": [ {"id": "t1", "from": ["x0"], "to": ["x1"], "guard": "start"} ],
  "outputs": { "fill_valve": "x1" },
  "forcing": [ {"by": "x11", "graph": "G1", "situation": ["x0"]} ],
  "owned": { "timer_done": {"step": "x1", "neutral": false, "preset": "TimerDuration"} }
}

Rules:
1. Step names start with the letter x followed by letters or digits (x0, x1, x21, xE1). The main graph is named G1, and x0 is its initial step.
2. A transition lists its upstream steps ("from"), its downstream steps ("to"), and its receptivity ("guard"). Guards use only the input identifiers of the task card, step names, the operators ! (not), & (and), | (or), parentheses, TRUE and FALSE; the level region of task T4 is tested as r = LOW, r = MID or r = HIGH.
3. "outputs" gives, for every output identifier of the task card, a Boolean expression over step names that is TRUE while the output is on.
4. "forcing" is optional: a separate graph (for example G0 for stop handling) may contain a step whose forcing order holds the graph named in "graph" in the listed situation.
5. "owned" lists every timer or hold condition used in a guard (timer_done, ton_q, tof_q, settled) with the step whose activity it measures, the value it has at the instant that step becomes active ("neutral"), and its preset, written as the parameter name of the task card ("preset"). Conditions that measure the duration of a step are FALSE at that instant; the off-delay output tof_q is measured by the pause step and is TRUE at that instant.
6. Output only the JSON object, without comments or explanations.
