# Hands-Off Sidecar — Per-Turn Template

USER: "{{transcript}}"

--- DESKTOP SNAPSHOT ---
{{#if stage_manager}}
Stage Manager: ON (grouping: {{sm_grouping}})

Active stage ({{active_count}} windows):
{{#each active_stage}}
  [{{wid}}] {{app}}: "{{title}}" — {{x}},{{y}} {{w}}x{{h}}
{{/each}}

Strip ({{strip_count}} thumbnails): {{strip_apps}}
Other stages: {{hidden_apps}}
{{else}}
Stage Manager: OFF

Visible windows ({{visible_count}}):
{{#each visible_windows}}
  [{{wid}}] {{app}}: "{{title}}" — {{x}},{{y}} {{w}}x{{h}}
{{/each}}
{{/if}}

{{#if current_layer}}
Current layer: {{layer_name}} (id: {{layer_id}})
{{/if}}

Screen: {{screen_w}}x{{screen_h}}, usable: {{usable_w}}x{{usable_h}}
--- END SNAPSHOT ---
