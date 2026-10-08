{{/*
NetworkPolicy allowing exactly the listed peers. Context dict:
  root, name, c (component values),
  from: list of { podSelector?, namespaceSelector?, ports? } ingress peers
  egressTo: list of { podSelector?, namespaceSelector?, ipBlock?, ports } egress rules
DNS egress is always allowed (default-deny blocks it otherwise).
*/}}
{{- define "shopstream-lib.networkPolicy" -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "shopstream-lib.fullname" . }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "shopstream-lib.selectorLabels" . | nindent 6 }}
  policyTypes: ["Ingress", "Egress"]
  {{- if not .from }}
  ingress: []
  {{- else }}
  ingress:
    {{- range .from }}
    - from:
        - {{- with .podSelector }}
          podSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .namespaceSelector }}
          namespaceSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with .ports }}
      ports:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
  {{- end }}
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - { port: 53, protocol: UDP }
        - { port: 53, protocol: TCP }
    {{- range .egressTo }}
    - to:
        {{- if .ipBlock }}
        - ipBlock:
            {{- toYaml .ipBlock | nindent 12 }}
        {{- else }}
        - {{- with .podSelector }}
          podSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .namespaceSelector }}
          namespaceSelector:
            {{- toYaml . | nindent 12 }}
          {{- end }}
        {{- end }}
      {{- with .ports }}
      ports:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
{{- end -}}
