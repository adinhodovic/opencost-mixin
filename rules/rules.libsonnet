{
  prometheusRules+:: {
    groups+: [
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
                  max by (%(clusterLabel)s, namespace, pod, persistentvolumeclaim) (kube_pod_spec_volumes_persistentvolumeclaims_info)
                  * on(%(clusterLabel)s, namespace, pod) group_left(workload_type, workload)
                  max by (%(clusterLabel)s, namespace, pod, workload_type, workload) (namespace_workload_pod:kube_pod_owner:relabel)
                )
                * on(%(clusterLabel)s, namespace, persistentvolumeclaim) group_left()
                sum by (%(clusterLabel)s, namespace, persistentvolumeclaim) (
                  (
                    sum by (%(clusterLabel)s, persistentvolume) (kube_persistentvolume_capacity_bytes / 1024 / 1024 / 1024)
                    * sum by (%(clusterLabel)s, persistentvolume) (pv_hourly_cost)
                  )
                  * on(%(clusterLabel)s, persistentvolume) group_left(persistentvolumeclaim, namespace)
                  max by (%(clusterLabel)s, persistentvolume, persistentvolumeclaim, namespace) (
                    label_replace(kube_persistentvolumeclaim_info, "persistentvolume", "$1", "volumename", "(.*)")
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
