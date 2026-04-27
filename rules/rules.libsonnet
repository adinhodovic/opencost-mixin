// Efficiency recording rules mirror OpenCost's native CPUEfficiency / RAMEfficiency /
// TotalEfficiency calculation. The numerator metrics (rate of
// container_cpu_usage_seconds_total, container_memory_working_set_bytes) and the
// container_name!="POD"/container!="POD" filter are taken from the same Prometheus
// queries OpenCost itself runs against cAdvisor:
//   QueryCPUUsageAvg / QueryRAMUsageAvg in
//   https://github.com/opencost/opencost/blob/develop/modules/prometheus-source/pkg/prom/metricsquerier.go
// The Allocation efficiency methods that combine these into the UI numbers:
//   CPUEfficiency / RAMEfficiency / TotalEfficiency in
//   https://github.com/opencost/opencost/blob/develop/core/pkg/opencost/allocation.go
// Spec: https://www.opencost.io/docs/specification#efficiency
//
// The allocation series (container_cpu_allocation, container_memory_allocation_bytes)
// are OpenCost's internal max(request, usage) × pod-uptime values, so using them
// as the denominator keeps dashboard numbers within ~2% of the OpenCost UI.
//
// rate(...[5m]) window: the rule group fires every 5m, so a 5m rate produces one
// fresh sample per evaluation; with kubelet scraping at 15–30s this gives
// ~10–20 samples per rate (well above Prometheus's "≥4 samples" rule of thumb).
{
  prometheusRules+:: {
    groups+: [
      {
        name: 'opencost.rules.efficiency',
        interval: '5m',
        rules: [
          {
            record: 'namespace:efficiency_cpu:ratio',
            expr: |||
              sum by (%(clusterLabel)s, namespace) (
                rate(container_cpu_usage_seconds_total{%(cadvisorSelector)s, container!="", container_name!="POD", container!="POD"}[5m])
              )
              /
              sum by (%(clusterLabel)s, namespace) (
                container_cpu_allocation{%(openCostSelector)s}
              )
            ||| % $._config,
          },
          {
            record: 'namespace:efficiency_ram:ratio',
            expr: |||
              sum by (%(clusterLabel)s, namespace) (
                container_memory_working_set_bytes{%(cadvisorSelector)s, container!="", container_name!="POD", container!="POD"}
              )
              /
              sum by (%(clusterLabel)s, namespace) (
                container_memory_allocation_bytes{%(openCostSelector)s}
              )
            ||| % $._config,
          },
          {
            record: 'namespace:opencost_cpu_cost:sum',
            expr: 'sum by (%(clusterLabel)s, namespace) (workload:opencost_cpu_cost:sum)' % $._config,
          },
          {
            record: 'namespace:opencost_ram_cost:sum',
            expr: 'sum by (%(clusterLabel)s, namespace) (workload:opencost_ram_cost:sum)' % $._config,
          },
          {
            record: 'namespace:efficiency_total:ratio',
            expr: |||
              (
                namespace:opencost_cpu_cost:sum * namespace:efficiency_cpu:ratio
                +
                namespace:opencost_ram_cost:sum * namespace:efficiency_ram:ratio
              )
              /
              (
                namespace:opencost_cpu_cost:sum + namespace:opencost_ram_cost:sum
              )
            |||,
          },
          {
            record: 'workload:efficiency_cpu:ratio',
            expr: |||
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                rate(container_cpu_usage_seconds_total{%(cadvisorSelector)s, container!="", container_name!="POD", container!="POD"}[5m])
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
              /
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                container_cpu_allocation{%(openCostSelector)s}
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
            ||| % $._config,
          },
          {
            record: 'workload:efficiency_ram:ratio',
            expr: |||
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                container_memory_working_set_bytes{%(cadvisorSelector)s, container!="", container_name!="POD", container!="POD"}
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
              /
              sum by (%(clusterLabel)s, namespace, workload_type, workload) (
                container_memory_allocation_bytes{%(openCostSelector)s}
                * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
              )
            ||| % $._config,
          },
          {
            record: 'workload:efficiency_total:ratio',
            expr: |||
              (
                workload:opencost_cpu_cost:sum * workload:efficiency_cpu:ratio
                +
                workload:opencost_ram_cost:sum * workload:efficiency_ram:ratio
              )
              /
              (
                workload:opencost_cpu_cost:sum + workload:opencost_ram_cost:sum
              )
            |||,
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
