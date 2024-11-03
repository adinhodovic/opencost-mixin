{
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
                    %s
                  }
                ) * 730
                or vector(0)
              )
              +
              (
                sum(
                  sum(
                    kube_persistentvolume_capacity_bytes{
                      %s
                    }
                    / 1024 / 1024 / 1024
                  ) by (persistentvolume)
                  *
                  sum(
                    pv_hourly_cost{
                      %s
                    }
                  ) by (persistentvolume)
                ) * 730
                or vector(0)
              )
              > %s
            ||| % [$._config.openCostSelector, $._config.openCostSelector, $._config.openCostSelector, $._config.alerts.budget.monthlyCostThreshold],
            labels: {
              severity: 'warning',
            },
            'for': '30m',
            annotations: {
              summary: 'OpenCost Monthly Budget Exceeded',
              description: 'The monthly budget for the cluster has been exceeded. Consider scaling down resources or increasing the budget.',
              dashboard_url: $._config.openCostOverviewDashboardUrl,
            },
          },
        ],
      },
    ]),
  },
}
