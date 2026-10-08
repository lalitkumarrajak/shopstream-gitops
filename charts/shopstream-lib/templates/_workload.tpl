{{/*
A complete, hardened stateless workload:
ServiceAccount + Deployment + Service (+ HPA, PDB, ServiceMonitor when enabled).
*/}}
{{- define "shopstream-lib.workload" -}}
{{- $fullname := include "shopstream-lib.fullname" . -}}
{{- $c := .c -}}
{{- $root := .root -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
automountServiceAccountToken: false
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
spec:
  {{- if not ($c.autoscaling).enabled }}
  replicas: {{ $c.replicas | default 1 }}
  {{- end }}
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      {{- include "shopstream-lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "shopstream-lib.labels" . | nindent 8 }}
      annotations:
        {{- with $c.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- with $c.configChecksum }}
        checksum/config: {{ . }}
        {{- end }}
    spec:
      serviceAccountName: {{ $fullname }}
      automountServiceAccountToken: false
      enableServiceLinks: false
      terminationGracePeriodSeconds: {{ $c.terminationGracePeriodSeconds | default 30 }}
      securityContext:
        {{- include "shopstream-lib.podSecurityContext" . | nindent 8 }}
      {{- with ($root.Values.global).imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $c.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              {{- include "shopstream-lib.selectorLabels" . | nindent 14 }}
      containers:
        - name: {{ .name }}
          image: {{ include "shopstream-lib.image" . | quote }}
          imagePullPolicy: {{ include "shopstream-lib.pullPolicy" . }}
          {{- with $c.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            - name: http
              containerPort: {{ $c.port }}
              protocol: TCP
          env:
            - name: PORT
              value: {{ $c.port | quote }}
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "k8s.pod.name=$(POD_NAME),k8s.namespace.name={{ $root.Release.Namespace }}"
            {{- range $k, $v := $c.env }}
            - name: {{ $k }}
              value: {{ tpl (toString $v) $root | quote }}
            {{- end }}
            {{- range $c.secretEnv }}
            - name: {{ . }}
              valueFrom:
                secretKeyRef:
                  name: {{ $c.secretName }}
                  key: {{ . }}
            {{- end }}
          {{- with $c.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $c.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- else }}
          startupProbe:
            httpGet:
              path: {{ ($c.probes).liveness | default "/health" }}
              port: http
            periodSeconds: 3
            failureThreshold: 40
          {{- end }}
          livenessProbe:
            httpGet:
              path: {{ ($c.probes).liveness | default "/health" }}
              port: http
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: {{ ($c.probes).readiness | default "/ready" }}
              port: http
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          resources:
            {{- toYaml $c.resources | nindent 12 }}
          securityContext:
            {{- include "shopstream-lib.containerSecurityContext" . | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- with $c.extraVolumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
      volumes:
        - name: tmp
          emptyDir:
            sizeLimit: 64Mi
        {{- with $c.extraVolumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "shopstream-lib.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ $c.port }}
      targetPort: http
      protocol: TCP
{{- if ($c.autoscaling).enabled }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $fullname }}
  minReplicas: {{ $c.autoscaling.minReplicas | default 2 }}
  maxReplicas: {{ $c.autoscaling.maxReplicas | default 5 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $c.autoscaling.targetCPUUtilizationPercentage | default 70 }}
    {{- with $c.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ . }}
    {{- end }}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
{{- end }}
{{- if ($c.pdb).enabled }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
spec:
  {{- if hasKey $c.pdb "minAvailable" }}
  minAvailable: {{ $c.pdb.minAvailable }}
  {{- else }}
  maxUnavailable: {{ $c.pdb.maxUnavailable | default 1 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "shopstream-lib.selectorLabels" . | nindent 6 }}
{{- end }}
{{- if and ($c.metrics).enabled (($root.Values.monitoring).serviceMonitor).enabled }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "shopstream-lib.labels" . | nindent 4 }}
    {{- with $root.Values.monitoring.serviceMonitor.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "shopstream-lib.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: http
      path: {{ $c.metrics.path | default "/metrics" }}
      interval: {{ $root.Values.monitoring.serviceMonitor.interval | default "30s" }}
      scrapeTimeout: 10s
      # keep the app's own `service` label (gateway, catalog, ...) instead of the k8s Service name
      honorLabels: true
{{- end }}
{{- end -}}
