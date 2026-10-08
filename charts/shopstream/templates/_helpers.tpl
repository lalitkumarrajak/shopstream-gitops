{{- define "shopstream.components" -}}
gateway catalog orders payments notifications web
{{- end -}}

{{- define "shopstream.backends" -}}
gateway catalog orders payments notifications
{{- end -}}

{{/* Builds the library context for one component: merges commonEnv into backend env and wires the secret. */}}
{{- define "shopstream.ctx" -}}
{{- $root := index . 0 -}}
{{- $name := index . 1 -}}
{{- $c := deepCopy (index $root.Values $name) -}}
{{- if has $name (splitList " " (include "shopstream.backends" $root)) -}}
{{- $_ := set $c "env" (merge (dict) ($c.env | default dict) $root.Values.commonEnv) -}}
{{- end -}}
{{- $_ := set $c "secretName" $root.Values.secretName -}}
{{- toYaml (dict "name" $name "c" $c) -}}
{{- end -}}

{{- define "shopstream.selector" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
