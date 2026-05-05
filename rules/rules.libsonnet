// Efficiency recording rules approximate OpenCost efficiency from exported
// Prometheus metrics. OpenCost does not export CPUEfficiency / RAMEfficiency /
// TotalEfficiency directly, so these rules use OpenCost allocation metrics as
// denominators. The numerator metrics (rate of container_cpu_usage_seconds_total,
// container_memory_working_set_bytes) and the container_name!="POD"/container!="POD"
// filter are taken from the same Prometheus queries OpenCost itself runs against
// cAdvisor:
//   QueryCPUUsageAvg / QueryRAMUsageAvg in
//   https://github.com/opencost/opencost/blob/develop/modules/prometheus-source/pkg/prom/metricsquerier.go
// OpenCost's native API/UI efficiency methods use request-average denominators:
//   CPUEfficiency / RAMEfficiency / TotalEfficiency in
//   https://github.com/opencost/opencost/blob/develop/core/pkg/opencost/allocation.go
// Spec: https://www.opencost.io/docs/specification#efficiency
//
// The allocation series (container_cpu_allocation, container_memory_allocation_bytes)
// are OpenCost's own exported allocation model (roughly max(request, usage)), so
// these rules report "usage / OpenCost allocation". This is allocation efficiency,
// not byte-for-byte parity with the OpenCost UI/API's request-based efficiency.
//
// rate(...[5m]) window: the rule group fires every 5m, so a 5m rate produces one
// fresh sample per evaluation; with kubelet scraping at 15–30s this gives
// ~10–20 samples per rate (well above Prometheus's "≥4 samples" rule of thumb).
{
  local clusterNamespace = '%(clusterLabel)s, namespace' % $._config,
  local clusterNamespacePod = '%(clusterLabel)s, namespace, pod' % $._config,
  local workloadLabels = '%(clusterLabel)s, namespace, workload_type, workload' % $._config,
  local cadvisorContainerSelector = '%(cadvisorSelector)s, container!="", container_name!="POD", container!="POD"' % $._config,
  local workloadOwner = 'max by (%s, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)' % clusterNamespacePod,
  local workloadEfficiency(metricExpr) = |||
    sum by (%(workloadLabels)s) (
      sum by (%(clusterNamespacePod)s) (
        %(metricExpr)s
      )
      * on(%(clusterNamespacePod)s) group_left(workload_type, workload)
      %(workloadOwner)s
    )
  ||| % {
    clusterNamespacePod: clusterNamespacePod,
    metricExpr: metricExpr,
    workloadLabels: workloadLabels,
    workloadOwner: workloadOwner,
  },
  local costWeightedEfficiencyTotal(scope, labels) = |||
    (
      %(scope)s:opencost_cpu_cost:sum
      * on(%(labels)s)
      %(scope)s:efficiency_cpu:ratio
      +
      %(scope)s:opencost_ram_cost:sum
      * on(%(labels)s)
      %(scope)s:efficiency_ram:ratio
    )
    /
    on(%(labels)s)
    (
      %(scope)s:opencost_cpu_cost:sum + %(scope)s:opencost_ram_cost:sum
    )
  ||| % {
    labels: labels,
    scope: scope,
  },
  prometheusRules+:: {
    groups+: [
      {
        name: 'opencost.rules.efficiency',
        interval: '5m',
        rules: [
          {
            record: 'namespace:efficiency_cpu:ratio',
            expr: |||
              sum by (%(clusterNamespace)s) (
                rate(container_cpu_usage_seconds_total{%(cadvisorContainerSelector)s}[5m])
              )
              /
              sum by (%(clusterNamespace)s) (
                container_cpu_allocation{%(openCostSelector)s}
              )
            ||| % ($._config {
                     cadvisorContainerSelector: cadvisorContainerSelector,
                     clusterNamespace: clusterNamespace,
                   }),
          },
          {
            record: 'namespace:efficiency_ram:ratio',
            expr: |||
              sum by (%(clusterNamespace)s) (
                container_memory_working_set_bytes{%(cadvisorContainerSelector)s}
              )
              /
              sum by (%(clusterNamespace)s) (
                container_memory_allocation_bytes{%(openCostSelector)s}
              )
            ||| % ($._config {
                     cadvisorContainerSelector: cadvisorContainerSelector,
                     clusterNamespace: clusterNamespace,
                   }),
          },
          {
            record: 'namespace:opencost_cpu_cost:sum',
            expr: 'sum by (%s) (workload:opencost_cpu_cost:sum)' % clusterNamespace,
          },
          {
            record: 'namespace:opencost_ram_cost:sum',
            expr: 'sum by (%s) (workload:opencost_ram_cost:sum)' % clusterNamespace,
          },
          {
            record: 'workload:efficiency_cpu:ratio',
            expr: |||
              %(workloadCpuUsage)s
              /
              %(workloadCpuAllocation)s
            ||| % {
              workloadCpuAllocation: workloadEfficiency('container_cpu_allocation{%(openCostSelector)s}' % $._config),
              workloadCpuUsage: workloadEfficiency('rate(container_cpu_usage_seconds_total{%(cadvisorContainerSelector)s}[5m])' % { cadvisorContainerSelector: cadvisorContainerSelector }),
            },
          },
          {
            record: 'workload:efficiency_ram:ratio',
            expr: |||
              %(workloadRamUsage)s
              /
              %(workloadRamAllocation)s
            ||| % {
              workloadRamAllocation: workloadEfficiency('container_memory_allocation_bytes{%(openCostSelector)s}' % $._config),
              workloadRamUsage: workloadEfficiency('container_memory_working_set_bytes{%(cadvisorContainerSelector)s}' % { cadvisorContainerSelector: cadvisorContainerSelector }),
            },
          },
          {
            record: 'namespace:efficiency_total:ratio',
            expr: costWeightedEfficiencyTotal('namespace', clusterNamespace),
          },
          {
            record: 'workload:efficiency_total:ratio',
            expr: costWeightedEfficiencyTotal('workload', workloadLabels),
          },
        ],
      },
      {
        name: 'opencost.rules.workload',
        interval: '5m',
        rules: [
          {
            record: 'workload:opencost_ram_cost:sum',
            expr: |||
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                (
                  sum by (%(clusterLabel)s, namespace, pod, instance) (container_memory_allocation_bytes)
                  * on(%(clusterLabel)s, instance) group_left()
                  (avg by (%(clusterLabel)s, instance) (node_ram_hourly_cost) / 1024 / 1024 / 1024)
                )
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
            ||| % $._config,
          },
          {
            record: 'workload:opencost_cpu_cost:sum',
            expr: |||
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                (
                  sum by (%(clusterLabel)s, namespace, pod, instance) (container_cpu_allocation)
                  * on(%(clusterLabel)s, instance) group_left()
                  avg by (%(clusterLabel)s, instance) (node_cpu_hourly_cost)
                )
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
            ||| % $._config,
          },
          {
            record: 'workload:opencost_pvc_cost:sum',
            expr: |||
              sum by (%(clusterLabel)s, namespace, persistentvolumeclaim, workload_type, workload) (
                max by (%(clusterLabel)s, namespace, persistentvolumeclaim, workload_type, workload) (
                  max by (%(clusterLabel)s, namespace, pod, persistentvolumeclaim) (kube_pod_spec_volumes_persistentvolumeclaims_info{%(kubeStateMetricsSelector)s})
                  * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                  max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
                )
                * on(%(clusterLabel)s, namespace, persistentvolumeclaim) group_left()
                sum by (%(clusterLabel)s, namespace, persistentvolumeclaim) (
                  (
                    sum by (%(clusterLabel)s, persistentvolume) (kube_persistentvolume_capacity_bytes{%(kubeStateMetricsSelector)s} / 1024 / 1024 / 1024)
                    * sum by (%(clusterLabel)s, persistentvolume) (pv_hourly_cost)
                  )
                  * on(%(clusterLabel)s, persistentvolume) group_left(persistentvolumeclaim, namespace)
                  max by (%(clusterLabel)s, persistentvolume, persistentvolumeclaim, namespace) (
                    label_replace(kube_persistentvolumeclaim_info{%(kubeStateMetricsSelector)s}, "persistentvolume", "$1", "volumename", "(.*)")
                  )
                )
              )
            ||| % $._config,
          },
          {
            record: 'workload:opencost_gpu_cost:sum',
            expr: |||
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                (
                  sum by (%(clusterLabel)s, namespace, pod, instance) (container_gpu_allocation)
                  * on(%(clusterLabel)s, instance) group_left()
                  avg by (%(clusterLabel)s, instance) (node_gpu_hourly_cost)
                )
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
            ||| % $._config,
          },
        ],
      },
    ],
  },
}
