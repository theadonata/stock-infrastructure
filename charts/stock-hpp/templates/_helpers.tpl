{{/*
Standard fullname prefix for every resource in this chart, e.g.
"stock-hpp-backend". Keeps names stable across dev/staging (same release
name convention in both Argo CD Applications) without hardcoding "stock-hpp"
in every template file.
*/}}
{{- define "stock-hpp.fullname" -}}
{{- .Chart.Name -}}
{{- end -}}

{{/*
Common labels applied to every resource, standard Helm/k8s recommended set.
*/}}
{{- define "stock-hpp.labels" -}}
app.kubernetes.io/part-of: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Component-specific selector labels, e.g. component=backend. Used on both the
Deployment's pod template and its Service selector so they stay in lockstep.
*/}}
{{- define "stock-hpp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}
