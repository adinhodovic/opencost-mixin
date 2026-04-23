local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local annotation = g.dashboard.annotation;

{
  _config+:: {
    local this = self,
    // Bypasses grafana.com/dashboards validator
    bypassDashboardValidation: {
      __inputs: [],
      __requires: [],
    },

    openCostSelector: 'job="opencost"',
    kubeStateMetricsSelector: 'job="kube-state-metrics"',

    // Default datasource name
    datasourceName: 'default',

    // Minimum interval for dashboard graphs. This is used to prevent Grafana from automatically adjusting the interval to a value that is too small, which can cause performance issues.
    dashboardMinInterval: '30m',

    // Opt-in to multiCluster dashboards by overriding this and the clusterLabel.
    showMultiCluster: false,
    clusterLabel: 'cluster',

    grafanaUrl: 'https://grafana.com',

    dashboardIds: {
      'opencost-overview': 'opencost-mixin-kover-jkwq',
      'opencost-namespace': 'opencost-mixin-namespace-jkwq',
      'opencost-workload': 'opencost-mixin-workload-jkwq',
    },
    dashboardUrls: {
      'opencost-overview': '%s/d/%s/opencost-overview' % [this.grafanaUrl, this.dashboardIds['opencost-overview']],
      'opencost-namespace': '%s/d/%s/opencost-namespace' % [this.grafanaUrl, this.dashboardIds['opencost-namespace']],
      'opencost-workload': '%s/d/%s/opencost-workload' % [this.grafanaUrl, this.dashboardIds['opencost-workload']],
    },

    alerts: {
      budget: {
        enabled: true,
        monthlyCostThreshold: 200,
      },
      anomaly: {
        enabled: true,
        anomalyPercentageThreshold: 15,
      },
      efficiency: {
        enabled: true,
        // Fire when namespace total (cost-weighted) efficiency falls below this ratio.
        minEfficiencyThreshold: 0.20,
        // Only evaluate namespaces whose projected monthly cost exceeds this USD amount.
        minMonthlyCostThreshold: 500,
        severity: 'info',
      },
    },

    tags: ['opencost', 'opencost-mixin'],

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Custom Annotation',
      datasource: '-- Grafana --',
      iconColor: 'green',
      tags: [],
    },

    customAnnotation:: if $._config.annotation.enabled then
      annotation.withName($._config.annotation.name) +
      annotation.withIconColor($._config.annotation.iconColor) +
      annotation.withHide(false) +
      annotation.datasource.withUid($._config.annotation.datasource) +
      annotation.target.withMatchAny(true) +
      annotation.target.withTags($._config.annotation.tags) +
      annotation.target.withType('tags')
    else {},
  },
}
