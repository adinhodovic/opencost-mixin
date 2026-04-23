{
  local clusterVariableQueryString = if $._config.showMultiCluster then '?var-%(clusterLabel)s={{ $labels.%(clusterLabel)s }}' % $._config else '',
  prometheusAlerts+:: {
    groups+: std.prune([
      if $._config.alerts.budget.enabled then {
        name: 'opencost',
        rules: [
          {
            alert: 'OpenCostMonthlyBudgetExceeded',
            expr: |||
              (
                sum(
                  node_total_hourly_cost{
                    %(openCostSelector)s
                  }
                ) by (%(clusterLabel)s) * 730
                or vector(0)
                +
                sum(
                  sum(
                    kube_persistentvolume_capacity_bytes{
                      %(openCostSelector)s
                    }
                    / 1024 / 1024 / 1024
                  ) by (%(clusterLabel)s, persistentvolume)
                  *
                  sum(
                    pv_hourly_cost{
                      %(openCostSelector)s
                    }
                  ) by (%(clusterLabel)s, persistentvolume)
                ) * 730
                or vector(0)
              )
              > %(monthlyCostThreshold)s
            ||| % ($._config { monthlyCostThreshold: $._config.alerts.budget.monthlyCostThreshold }),
            labels: {
              severity: 'warning',
            },
            'for': '30m',
            annotations: {
              summary: 'OpenCost Monthly Budget Exceeded',
              description: 'The monthly budget for the cluster has been exceeded. Consider scaling down resources or increasing the budget.',
              dashboard_url: $._config.dashboardUrls['opencost-overview'] + clusterVariableQueryString,
            },
          },
          {
            alert: 'OpenCostAnomalyDetected',
            expr: |||
              (
                (
                  (
                    avg_over_time(
                      sum(
                        node_total_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [3h:30m]
                    )
                    or vector(0)
                  )
                  +
                  (
                    avg_over_time(
                      sum(
                        (
                          kube_persistentvolume_capacity_bytes{
                            %(openCostSelector)s
                          } / 1024 / 1024 / 1024
                        )
                        * on (%(clusterLabel)s, persistentvolume)
                        group_left()
                        pv_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [3h:30m]
                    )
                    or vector(0)
                  )
                )
                -
                (
                  (
                    avg_over_time(
                      sum(
                        node_total_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [7d:30m]
                    )
                    or vector(0)
                  )
                  +
                  (
                    avg_over_time(
                      sum(
                        (
                          kube_persistentvolume_capacity_bytes{
                            %(openCostSelector)s
                          } / 1024 / 1024 / 1024
                        )
                        * on (%(clusterLabel)s, persistentvolume)
                        group_left()
                        pv_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [7d:30m]
                    )
                    or vector(0)
                  )
                )
              )
              /
              (
                (
                  (
                    avg_over_time(
                      sum(
                        node_total_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [7d:30m]
                    )
                    or vector(0)
                  )
                  +
                  (
                    avg_over_time(
                      sum(
                        (
                          kube_persistentvolume_capacity_bytes{
                            %(openCostSelector)s
                          } / 1024 / 1024 / 1024
                        )
                        * on (%(clusterLabel)s, persistentvolume)
                        group_left()
                        pv_hourly_cost{
                          %(openCostSelector)s
                        }
                      ) by (%(clusterLabel)s) [7d:30m]
                    )
                    or vector(0)
                  )
                )
              )
              > (%(anomalyPercentageThreshold)s / 100)
            ||| % ($._config { anomalyPercentageThreshold: $._config.alerts.anomaly.anomalyPercentageThreshold }),
            labels: {
              severity: 'warning',
            },
            'for': '10m',
            annotations: {
              summary: 'OpenCost Cost Anomaly Detected',
              description: 'A significant increase in cluster costs has been detected. The average hourly cost over the 3 hours exceeds the 7-day average by more than %s%%. This could indicate unexpected resource usage or cost-related changes in the cluster.' % $._config.alerts.anomaly.anomalyPercentageThreshold,
              dashboard_url: $._config.dashboardUrls['opencost-overview'] + clusterVariableQueryString,
            },
          },
        ],
      },
      if $._config.alerts.efficiency.enabled then {
        name: 'opencost-efficiency',
        rules: [
          {
            // Fires when a namespace's cost-weighted efficiency stays below the
            // configured threshold over 7d AND the namespace is spending more
            // than minMonthlyCostThreshold. Mirrors OpenCost's native formula
            // (see core/pkg/opencost/allocation.go — CPUEfficiency, RAMEfficiency,
            // TotalEfficiency). Spec: https://www.opencost.io/docs/specification#efficiency
            alert: 'OpenCostLowEfficiencyNamespace',
            expr: |||
              avg_over_time(namespace:efficiency_total:ratio[7d]) < %(minEfficiencyThreshold)s
              and
              (
                avg_over_time(namespace:opencost_cpu_cost:sum[7d])
                + avg_over_time(namespace:opencost_ram_cost:sum[7d])
              ) * 730 > %(minMonthlyCostThreshold)s
            ||| % $._config.alerts.efficiency,
            labels: {
              severity: $._config.alerts.efficiency.severity,
            },
            'for': '1h',
            annotations: {
              summary: 'Namespace {{ $labels.namespace }} on {{ $labels.%(clusterLabel)s }} is chronically under-utilizing its requests' % $._config,
              description: ('Total CPU+RAM cost-weighted efficiency for namespace {{ $labels.namespace }} on cluster {{ $labels.%(clusterLabel)s }} has averaged {{ $value | humanizePercentage }} over the last 7 days while projected monthly cost exceeds $%(minMonthlyCostThreshold)s. Consider rightsizing container requests. Formula mirrors OpenCost allocation.go (CPUEfficiency, RAMEfficiency, TotalEfficiency) — spec at https://www.opencost.io/docs/specification#efficiency.') % ($._config { minMonthlyCostThreshold: $._config.alerts.efficiency.minMonthlyCostThreshold }),
              dashboard_url: $._config.dashboardUrls['opencost-namespace'] + clusterVariableQueryString,
            },
          },
        ],
      },
    ]),
  },
}
