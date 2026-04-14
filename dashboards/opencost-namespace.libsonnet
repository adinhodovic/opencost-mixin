local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local dashboards = mixinUtils.dashboards;
local util = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local tablePanel = g.panel.table;

// Table
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbFieldConfig = tablePanel.fieldConfig;
local tbOverride = tbStandardOptions.override;

{
  local dashboardName = 'opencost-namespace',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
        defaultVariables.namespace,
      ];

      local defaultFilters = util.filters($._config);
      local queries = {
        monthlyRamCost: |||
          sum(
            sum(
              container_memory_allocation_bytes{
                %(withNamespace)s
              }
            )
            by (namespace, instance)
            * on(instance) group_left()
            (
              avg(
                node_ram_hourly_cost{
                  %(default)s
                }
              ) by (instance) / (1024 * 1024 * 1024) * 730
            )
          )
        ||| % defaultFilters,

        monthlyCpuCost: |||
          sum(
            sum(
              container_cpu_allocation{
                %(withNamespace)s
              }
            )
            by (namespace, instance)
            * on(instance) group_left()
            (
              avg(
                node_cpu_hourly_cost{
                  %(default)s
                }
              ) by (instance) * 730
            )
          )
        ||| % defaultFilters,

        monthlyPVCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              }
              / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            *
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace) (
              label_replace(
                kube_persistentvolumeclaim_info{
                  %(withNamespace)s
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
            )
          ) * 730
        ||| % defaultFilters,

        monthlyPVNoNilCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              }
              / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            *
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace) (
              label_replace(
                kube_persistentvolumeclaim_info{
                  %(withNamespace)s
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
            ) or vector(0)
          ) * 730
        ||| % defaultFilters,

        monthlyCost: |||
          %s
          +
          %s
          +
          %s
        ||| % [queries.monthlyRamCost, queries.monthlyCpuCost, queries.monthlyPVNoNilCost],
        dailyCost: std.strReplace(queries.monthlyCost, ') * 730', ') * 24'),
        hourlyCost: std.strReplace(queries.monthlyCost, ') * 730', ') * 1'),

        // Keep job label formatting inconsistent due to strReplace
        podMonthlyCost: |||
          topk(10,
            sum(
              (
                sum(
                  container_memory_allocation_bytes{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, pod)
                * on(instance) group_left()
                (
                  avg(
                    node_ram_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) / (1024 * 1024 * 1024) * 730
                )
              )
              +
              (
                sum(
                  container_cpu_allocation{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, pod)
                * on(instance) group_left()
                (
                  avg(
                    node_cpu_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) * 730)
              )
            ) by (pod)
          )
        ||| % defaultFilters,
        podMonthlyCostOffset7d: std.strReplace(queries.podMonthlyCost, 'job="$job"}', 'job="$job"} offset 7d'),
        podMonthlyCostOffset30d: std.strReplace(queries.podMonthlyCost, 'job="$job"}', 'job="$job"} offset 30d'),

        podMonthlyCostDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.podMonthlyCost,
          queries.podMonthlyCostOffset7d,
        ],
        podMonthlyCostDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.podMonthlyCost,
          queries.podMonthlyCostOffset30d,
        ],

        containerMonthlyCost: |||
          topk(10,
            sum(
              (
                sum(
                  container_memory_allocation_bytes{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, container)
                * on(instance) group_left()
                (
                  avg(
                    node_ram_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) / (1024 * 1024 * 1024) * 730
                )
              )
              +
              (
                sum(
                  container_cpu_allocation{
                    %(cluster)s,
                    %(namespace)s,
                    %(job)s}
                )
                by (instance, container)
                * on(instance) group_left()
                (
                  avg(
                    node_cpu_hourly_cost{
                      %(cluster)s,
                      %(job)s}
                  ) by (instance) * 730
                )
              )
            ) by (container)
          )
        ||| % defaultFilters,
        containerMonthlyCostOffset7d: std.strReplace(queries.containerMonthlyCost, 'job="$job"}', 'job="$job"} offset 7d'),
        containerMonthlyCostOffset30d: std.strReplace(queries.containerMonthlyCost, 'job="$job"}', 'job="$job"} offset 30d'),

        containerMonthlyCostDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.containerMonthlyCost,
          queries.containerMonthlyCostOffset7d,
        ],
        containerMonthlyCostDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [
          queries.containerMonthlyCost,
          queries.containerMonthlyCostOffset30d,
        ],

        pvTotalGibByPvQuery: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                cluster="$cluster",
                job="$job"
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left(cluster, namespace)
              label_replace(
                kube_persistentvolumeclaim_info{
                  cluster="$cluster",
                  job="$job",
                  namespace="$namespace"
                },
                "persistentvolume", "$1",
                "volumename", "(.*)"
              )
          ) by (persistentvolume)
        ||| % defaultFilters,
        pvMonthlyCostByPv: std.strReplace(queries.monthlyPVCost, '* 730', 'by (persistentvolume) * 730'),
      };

      local panels = {
        hourlyCostStat:
          dashboards.statPanel(
            'Hourly Cost',
            'currencyUSD',
            queries.hourlyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Current hourly cost rate for the selected namespace, including CPU, RAM, and PV costs. This provides real-time visibility into namespace spending and helps track the immediate impact of workload changes on costs.',
          ),

        dailyCostStat:
          dashboards.statPanel(
            'Daily Cost',
            'currencyUSD',
            queries.dailyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Total daily cost for the selected namespace. The percentage change indicates cost variance compared to the previous period, helping application teams monitor their daily spending and detect unexpected cost increases.',
          ),

        monthlyCostStat:
          dashboards.statPanel(
            'Monthly Cost',
            'currencyUSD',
            queries.monthlyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Projected monthly cost for the selected namespace based on current hourly rates. Application teams can use this to track their budget allocation and ensure they stay within their cost targets.',
          ),

        monthlyRamCostStat:
          dashboards.statPanel(
            'Monthly Ram Cost',
            'currencyUSD',
            queries.monthlyRamCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Projected monthly RAM cost for the selected namespace. High memory costs may indicate opportunities to optimize container memory requests or identify memory-intensive workloads that could benefit from tuning.',
          ),

        monthlyCpuCostStat:
          dashboards.statPanel(
            'Monthly CPU Cost',
            'currencyUSD',
            queries.monthlyCpuCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Projected monthly CPU cost for the selected namespace. Compare this with RAM costs to understand your namespace compute profile and identify if CPU requests are appropriately sized for your workloads.',
          ),

        monthlyPVCostStat:
          dashboards.statPanel(
            'Monthly PV Cost',
            'currencyUSD',
            queries.monthlyPVCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Projected monthly Persistent Volume cost for the selected namespace. Monitor this to identify unused PVCs or opportunities to migrate to cheaper storage classes without impacting application performance.',
          ),

        dailyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Daily Cost',
            'currencyUSD',
            [
              {
                expr: queries.dailyCost,
                legend: 'Daily Cost',
                interval: '1h',
              },
            ],
            description='Daily cost trend for the selected namespace over time. Use this to track how namespace costs evolve, identify cost spikes related to deployments or scaling events, and validate that cost optimization efforts are effective.',
          ),

        monthlyCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.monthlyCost,
                legend: 'Monthly Cost',
                interval: '1h',
              },
            ],
            description='Monthly cost projection trend for the selected namespace. This helps application teams track their projected monthly spending and ensure they remain within their allocated budget throughout the billing period.',
          ),

        resourceCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Resource',
            'currencyUSD',
            [
              {
                expr: queries.monthlyCpuCost,
                legend: 'CPU',
              },
              {
                expr: queries.monthlyRamCost,
                legend: 'RAM',
              },
              {
                expr: queries.monthlyPVCost,
                legend: 'PV',
              },
            ],
            description='Monthly cost distribution for the selected namespace across resource types (CPU, RAM, Persistent Volumes). This shows which resource category is the primary cost driver for this namespace, helping teams prioritize their optimization efforts.',
            values=['percent', 'value']
          ),

        podTable:
          dashboards.tablePanel(
            'Pod Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.podMonthlyCost,
              },
              {
                expr: queries.podMonthlyCostDifference7d,
              },
              {
                expr: queries.podMonthlyCostDifference30d,
              },
            ],
            description='Top 10 pods by projected monthly cost (based on current hourly rates) with percentage change compared to 7 days and 30 days ago. Positive percentages indicate cost increases (red), negative percentages indicate cost decreases (green). Use this to identify the most expensive pods in the namespace and track how pod costs change over time, especially after deployments or configuration changes.',
            sortBy={
              name: 'Total Cost (Today)',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    pod: 'Pod',
                    'Value #A': 'Monthly Cost',
                    'Value #B': 'Cost Change vs 7d Ago (%)',
                    'Value #C': 'Cost Change vs 30d Ago (%)',
                  },
                  indexByName: {
                    pod: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                    'Value #C': 3,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Cost Change vs 7d Ago (%)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
              tbOverride.byName.new('Cost Change vs 30d Ago (%)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
            ],
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(5) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(10) +
              tbStandardOptions.threshold.step.withColor('red'),
            ]
          ),

        podCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Pod',
            'currencyUSD',
            [
              {
                expr: queries.podMonthlyCost,
                legend: '{{ pod }}',
              },
            ],
            values=['percent', 'value'],
            description='Top 10 pods by monthly cost showing the distribution of spending across pods in the namespace. This visualization helps identify which pods consume the most resources and whether costs are evenly distributed or concentrated in a few workloads.',
          ),

        containerTable:
          dashboards.tablePanel(
            'Container Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.containerMonthlyCost,
              },
              {
                expr: queries.containerMonthlyCostDifference7d,
              },
              {
                expr: queries.containerMonthlyCostDifference30d,
              },
            ],
            description='Top 10 containers by current monthly cost with percentage change compared to 7 days and 30 days ago. Positive percentages indicate cost increases (red), negative percentages indicate cost decreases (green). This granular view helps identify specific containers within pods that are driving costs, useful for optimizing multi-container pod configurations.',
            sortBy={
              name: 'Monthly Cost',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    container: 'Container',
                    'Value #A': 'Monthly Cost',
                    'Value #B': 'Cost Change vs 7d Ago (%)',
                    'Value #C': 'Cost Change vs 30d Ago (%)',
                  },
                  indexByName: {
                    container: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                    'Value #C': 3,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Cost Change vs 7d Ago (%)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
              tbOverride.byName.new('Cost Change vs 30d Ago (%)') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percent') +
                tbFieldConfig.defaults.custom.withCellOptions(
                  { type: 'color-background' }  // TODO(adinhodovic): Use jsonnet lib
                ) +
                tbStandardOptions.color.withMode('thresholds')
              ),
            ],
            steps=[
              tbStandardOptions.threshold.step.withValue(0) +
              tbStandardOptions.threshold.step.withColor('green'),
              tbStandardOptions.threshold.step.withValue(5) +
              tbStandardOptions.threshold.step.withColor('yellow'),
              tbStandardOptions.threshold.step.withValue(10) +
              tbStandardOptions.threshold.step.withColor('red'),
            ]
          ),

        containerCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Container',
            'currencyUSD',
            [
              {
                expr: queries.containerMonthlyCost,
                legend: '{{ container }}',
              },
            ],
            values=['percent', 'value'],
            description='Top 10 containers by monthly cost showing the distribution of spending across containers in the namespace. This helps identify which container images or workload types are most expensive and whether sidecar containers are adding significant costs.',
          ),

        pvTable:
          dashboards.tablePanel(
            'Persistent Volumes Monthly Cost',
            'decgbytes',
            [
              {
                expr: queries.pvTotalGibByPvQuery,
              },
              {
                expr: queries.pvMonthlyCostByPv,
              },
            ],
            description='List of Persistent Volumes used by the selected namespace with their capacity (in GiB) and monthly cost, sorted by total cost. Use this to identify large or expensive volumes that may be candidates for cleanup, resizing, or migration to cheaper storage classes.',
            sortBy={
              name: 'Monthly Cost',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    persistentvolume: 'Persistent Volume',
                    'Value #A': 'Total GiB',
                    'Value #B': 'Total Cost',
                  },
                  indexByName: {
                    persistentvolume: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                    namespace: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Total Cost') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('currencyUSD')
              ),
            ]
          ),

        pvCostPieChart:
          dashboards.pieChartPanel(
            'Cost by Persistent Volume',
            'currencyUSD',
            [
              {
                expr: queries.pvMonthlyCostByPv,
                legend: '{{ persistentvolume }}',
              },
            ],
            values=['percent', 'value'],
            description='Distribution of monthly storage costs across Persistent Volumes in the namespace. This shows which volumes consume the most storage budget and helps identify if storage costs are concentrated in a few large volumes or distributed across many smaller ones.',
          ),
      };

      local rows =
        [
          row.new(
            'Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.hourlyCostStat,
            panels.dailyCostStat,
            panels.monthlyCostStat,
            panels.monthlyCpuCostStat,
            panels.monthlyRamCostStat,
            panels.monthlyPVCostStat,
          ],
          panelWidth=4,
          panelHeight=3,
          startY=1
        ) +
        grid.wrapPanels(
          [
            panels.dailyCostTimeSeries,
            panels.monthlyCostTimeSeries,
            panels.resourceCostPieChart,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=4
        ) +
        [
          row.new(
            'Pod Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(9) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.podTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(10) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.podCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(10) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ] +
        [
          row.new(
            'Container Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.containerTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.containerCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(21) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ] +
        [
          row.new(
            'PV Summary',
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(31) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.pvTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(32) +
          tablePanel.gridPos.withW(18) +
          tablePanel.gridPos.withH(10),
          panels.pvCostPieChart +
          row.gridPos.withX(18) +
          row.gridPos.withY(32) +
          row.gridPos.withW(6) +
          row.gridPos.withH(10),
        ];

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'OpenCost / Namespace',
      ) +
      dashboard.withDescription('A detailed namespace-level cost analysis dashboard that breaks down infrastructure spending by pods, containers, and persistent volumes within a selected namespace. Use this dashboard to understand which workloads are driving costs within a namespace, track cost trends over time, and identify optimization opportunities at the pod and container level. This dashboard is ideal for application teams monitoring their own resource consumption and costs. %s' % mixinUtils.dashboards.dashboardDescriptionLink('opencost-mixin', 'https://github.com/adinhodovic/opencost-mixin')) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-2d') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        mixinUtils.dashboards.dashboardLinks('OpenCost', $._config)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        mixinUtils.dashboards.annotations($._config, defaultFilters)
      ),
  },
}
