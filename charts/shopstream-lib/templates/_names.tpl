{{/*
Naming and labelling helpers. Every template receives a context dict:
  root: the top-level chart context ($)
  name: component name (gateway, catalog, ...)
  c:    the component's values
*/}}

{{- define "shopstream-lib.chartLabel" -}}
{{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "shopstream-lib.fullname" -}}
{{- printf "%s-%s" .root.Release.Name .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shopstream-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{- define "shopstream-lib.labels" -}}
{{ include "shopstream-lib.selectorLabels" . }}
app.kubernetes.io/part-of: shopstream
app.kubernetes.io/component: {{ .c.component | default "service" }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/version: {{ include "shopstream-lib.imageTag" . | quote }}
helm.sh/chart: {{ include "shopstream-lib.chartLabel" .root }}
{{- end -}}

{{- define "shopstream-lib.imageTag" -}}
{{- $g := .root.Values.global | default dict -}}
{{- $gi := $g.image | default dict -}}
{{- (.c.image).tag | default $gi.tag | default .root.Chart.AppVersion -}}
{{- end -}}

{{/* registry/repository:tag, or repository@digest when a digest is pinned */}}
{{- define "shopstream-lib.image" -}}
{{- $g := .root.Values.global | default dict -}}
{{- $gi := $g.image | default dict -}}
{{- $repo := .c.image.repository -}}
{{- $registry := .c.image.registry | default $gi.registry -}}
{{- $full := ternary (printf "%s/%s" $registry $repo) $repo (not (empty $registry)) -}}
{{- if .c.image.digest -}}
{{ printf "%s@%s" $full .c.image.digest }}
{{- else -}}
{{ printf "%s:%s" $full (include "shopstream-lib.imageTag" .) }}
{{- end -}}
{{- end -}}

{{- define "shopstream-lib.pullPolicy" -}}
{{- $g := .root.Values.global | default dict -}}
{{- $gi := $g.image | default dict -}}
{{- .c.image.pullPolicy | default $gi.pullPolicy | default "IfNotPresent" -}}
{{- end -}}

{{/* Restricted Pod Security Standard compliant pod security context. */}}
{{- define "shopstream-lib.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: {{ .c.runAsUser | default 10001 }}
runAsGroup: {{ .c.runAsGroup | default .c.runAsUser | default 10001 }}
fsGroup: {{ .c.fsGroup | default .c.runAsGroup | default .c.runAsUser | default 10001 }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "shopstream-lib.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
privileged: false
capabilities:
  drop: ["ALL"]
{{- end -}}
