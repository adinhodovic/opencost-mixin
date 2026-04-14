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
local tbPanelOptions = tablePanel.panelOptions;
local tbOverride = tbStandardOptions.override;


{
  local dashboardName = 'opencost-overview',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = util.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.job,
      ];

      local defaultFilters = util.filters($._config);
      local queries = {
        dailyCost: |||
          sum(
            node_total_hourly_cost{
              %(default)s
            }
          ) * 24
          +
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left()
            sum(
              pv_hourly_cost{
                %(default)s
              }
            ) by (persistentvolume)
          ) * 24
        ||| % defaultFilters,
        hourlyCost: std.strReplace(queries.dailyCost, '* 24', ''),
        monthlyCost: std.strReplace(queries.dailyCost, '* 24', '* 730'),

        monthlyRamCost: |||
          sum(
            sum(
              kube_node_status_capacity{
                %(default)s,
                resource="memory",
                unit="byte"
              }
            ) by (node)
            / (1024 * 1024 * 1024)
            * on(node) group_left()
              sum(
                node_ram_hourly_cost{
                  %(default)s
                }
              ) by (node)
            * 730
          )
        ||| % defaultFilters,

        monthlyCpuCost: |||
          sum(
            sum(
              kube_node_status_capacity{
                %(default)s,
                resource="cpu",
                unit="core"
              }
            ) by (node)
            * on(node) group_left()
              sum(
                node_cpu_hourly_cost{
                  %(default)s
                }
              ) by (node)
            * 730
          )
        ||| % defaultFilters,

        monthlyPVCost: |||
          sum(
            sum(
              kube_persistentvolume_capacity_bytes{
                %(default)s
              } / (1024 * 1024 * 1024)
            ) by (persistentvolume)
            * on(persistentvolume) group_left()
              sum(
                pv_hourly_cost{
                  %(default)s
                }
              ) by (persistentvolume)
          ) * 730
        ||| % defaultFilters,

        nodeMonthlyCpuCost: |||
          sum(
            kube_node_status_capacity{
              %(default)s,
              resource="cpu",
              unit="core"
            }
          ) by (node)
          * on(node) group_left(cluster, instance_type, arch)
            sum(
              node_cpu_hourly_cost{
                %(default)s,
              }
            ) by (node, instance_type, arch)
          * 730
        ||| % defaultFilters,

        nodeMonthlyRamCost: |||
          sum(
            kube_node_status_capacity{
              %(default)s,
              resource="memory",
              unit="byte"
            }
          ) by (node)
          / (1024 * 1024 * 1024)
          * on(node) group_left(cluster, instance_type, arch)
            sum(
              node_ram_hourly_cost{
                %(default)s
              }
            ) by (node, instance_type, arch)
          * 730
        ||| % defaultFilters,

        totalCostVariance7d: |||
          (
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [1d:1h]
            )
            -
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [7d:1h]
            )
          )
          /
          avg_over_time(
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) [7d:1h]
          )
        ||| % defaultFilters,

        totalCostVariance30d: |||
          (
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [1d:1h]
            )
            -
            avg_over_time(
              sum(
                node_total_hourly_cost{
                  %(default)s
                }
              ) [30d:1h]
            )
          )
          /
          avg_over_time(
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) [30d:1h]
          )
        ||| % defaultFilters,

        cpuCostVariance30d: |||
          (
            avg_over_time(
              %s [1d:1h]
            )
            -
            avg_over_time(
              %s [30d:1h]
            )
          )
          /
          avg_over_time(
            %s [30d:1h]
          )
        ||| % [queries.monthlyCpuCost, queries.monthlyCpuCost, queries.monthlyCpuCost],

        ramCostVariance30d: |||
          (
            avg_over_time(
              %s [1d:1h]
            )
            -
            avg_over_time(
              %s [30d:1h]
            )
          )
          /
          avg_over_time(
            %s [30d:1h]
          )
        ||| % [queries.monthlyRamCost, queries.monthlyRamCost, queries.monthlyRamCost],

        pvCostVariance30d: |||
          (
            avg_over_time(
              (%s) [1d:1h]
            )
            -
            avg_over_time(
              (%s) [30d:1h]
            )
          )
          /
          avg_over_time(
            (%s) [30d:1h]
          )
        ||| % [queries.monthlyPVCost, queries.monthlyPVCost, queries.monthlyPVCost],

        // Keep job label formatting inconsistent due to strReplace
        namespaceMonthlyCost: |||
          topk(10,
            sum(
              sum(
                container_memory_allocation_bytes{
                  %(cluster)s,
                  %(job)s}
              ) by (namespace, instance)
              * on(instance) group_left()
                (
                  node_ram_hourly_cost{
                    %(cluster)s,
                    %(job)s} / (1024 * 1024 * 1024) * 730
                )
              +
              sum(
                container_cpu_allocation{
                  %(cluster)s,
                  %(job)s}
              ) by (namespace, instance)
              * on(instance) group_left()
                (
                  node_cpu_hourly_cost{
                    %(cluster)s,
                    %(job)s} * 730
                )
            ) by (namespace)
          )
        ||| % defaultFilters,

        monthlyCostOffset7d: std.strReplace(queries.namespaceMonthlyCost, 'job="$job"}', 'job="$job"} offset 7d'),
        monthlyCostOffset30d: std.strReplace(queries.namespaceMonthlyCost, 'job="$job"}', 'job="$job"} offset 30d'),

        costDifference7d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [queries.namespaceMonthlyCost, queries.monthlyCostOffset7d],
        costDifference30d: |||
          %s
          /
          %s
          * 100
          - 100
        ||| % [queries.namespaceMonthlyCost, queries.monthlyCostOffset30d],

        instanceTypeCost: |||
          topk(10,
            sum(
              node_total_hourly_cost{
                %(default)s
              }
            ) by (instance_type) * 730
          )
        ||| % defaultFilters,

        nodeTotalCost: |||
          sum(
            node_total_hourly_cost{
              %(default)s
            }
          ) by (node, instance_type, arch)
          * 730
        ||| % defaultFilters,

        pvTotalGib: |||
          sum(
            kube_persistentvolume_capacity_bytes{
              %(default)s
            }
            / 1024 / 1024 / 1024
          ) by (persistentvolume)
        ||| % defaultFilters,

        pvMonthlyCost: |||
          sum(
            kube_persistentvolume_capacity_bytes{
              %(default)s
            }
            / 1024 / 1024 / 1024
          ) by (persistentvolume)
          *
          sum(
            pv_hourly_cost{
              %(default)s
            }
            * 730
          ) by (persistentvolume)
        ||| % defaultFilters,
      };

      local panels = {
        dailyCostStat:
          dashboards.statPanel(
            'Daily Cost',
            'currencyUSD',
            queries.dailyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Total daily infrastructure cost across the cluster, including compute (CPU, RAM) and storage (PV) costs. The percentage change indicates cost variance compared to the previous period, helping identify sudden cost increases or decreases.',
          ),

        hourlyCostStat:
          dashboards.statPanel(
            'Hourly Cost',
            'currencyUSD',
            queries.hourlyCost,
            graphMode='none',
            decimals=2,
            showPercentChange=true,
            percentChangeColorMode='inverted',
            description='Current hourly infrastructure cost rate across the cluster. This metric provides real-time cost visibility and can be used to project daily and monthly spending. The percentage change helps track cost fluctuations over time.',
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
            description='Projected monthly infrastructure cost based on current hourly rates (730 hours per month). This projection helps with budget planning and cost forecasting. Compare this value against your budget to ensure spending stays within limits.',
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
            description='Projected monthly cost for RAM (memory) resources across all cluster nodes. This metric helps identify if memory is a significant cost driver and can guide decisions about node sizing and memory allocation strategies.',
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
            description='Projected monthly cost for CPU (compute) resources across all cluster nodes. Compare this with RAM costs to understand your compute vs. memory cost ratio and optimize instance type selection accordingly.',
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
            description='Projected monthly cost for Persistent Volume (storage) resources across the cluster. Monitor this metric to identify unused or oversized volumes that can be optimized to reduce storage costs.',
          ),

        hourCostTimeSeries:
          dashboards.timeSeriesPanel(
            'Hourly Cost',
            'currencyUSD',
            queries.hourlyCost,
            'Hourly Cost',
            description='Hourly cost trend over time showing how infrastructure spending fluctuates throughout the day. Use this to identify cost spikes, correlate costs with workload patterns, and detect autoscaling behavior impact on spending.',
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
            description='Daily cost trend showing infrastructure spending patterns over multiple days. This view helps identify day-over-day cost changes, weekly patterns, and the impact of infrastructure changes on overall spending.',
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
            description='Monthly cost projection trend over time. This visualization helps track how your projected monthly spending evolves and whether you are staying within budget throughout the billing period.',
          ),

        totalCostVarianceTimeSeries:
          dashboards.timeSeriesPanel(
            'Total Cost Variance',
            'percentunit',
            [
              {
                expr: queries.totalCostVariance7d,
                legend: 'Current hourly cost vs. 7-day average',
                interval: '1h',
              },
              {
                expr: queries.totalCostVariance30d,
                legend: 'Current hourly cost vs. 30-day average',
                interval: '1h',
              },
            ],
            description='Cost variance comparing current hourly costs against 7-day and 30-day historical averages. Positive values indicate costs are higher than average, negative values indicate lower costs. Use this to detect cost anomalies and unusual spending patterns that may require investigation.',
          ),

        resourceCostVarianceTimeSeries:
          dashboards.timeSeriesPanel(
            'Resource Cost Variance',
            'percentunit',
            [
              {
                expr: queries.cpuCostVariance30d,
                legend: 'CPU Cost vs. 30-day average',
                interval: '1h',
              },
              {
                expr: queries.ramCostVariance30d,
                legend: 'RAM Cost vs. 30-day average',
                interval: '1h',
              },
              {
                expr: queries.pvCostVariance30d,
                legend: 'PV Cost vs. 30-day average',
                interval: '1h',
              },
            ],
            description='Resource-specific cost variance comparing current CPU, RAM, and PV costs against their 30-day historical averages. This breakdown helps identify which resource type is driving cost changes - useful for pinpointing whether cost increases are due to compute scaling, memory usage, or storage growth.',
          ),

        resourceCostPieChartPanel:
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
            description='Monthly cost distribution across resource types (CPU, RAM, Persistent Volumes). This breakdown shows which resource category consumes the most budget, helping prioritize optimization efforts. For example, if PV costs dominate, focus on storage optimization.',
            values=['percent', 'value']
          ),

        namespaceCostPieChartPanel:
          dashboards.pieChartPanel(
            'Cost by Namespace',
            'currencyUSD',
            queries.namespaceMonthlyCost,
            '{{ namespace }}',
            description='Top 10 namespaces by monthly cost showing which teams, applications, or environments consume the most resources. Use this to allocate costs to teams, identify expensive applications, and ensure fair resource distribution across the organization.',
            values=['percent', 'value']
          ),

        instanceTypeCostPieChartPanel:
          dashboards.pieChartPanel(
            'Cost by Instance Type',
            'currencyUSD',
            queries.instanceTypeCost,
            '{{ instance_type }}',
            description='Top 10 instance types by monthly cost showing which VM/node types contribute most to infrastructure spending. This helps evaluate whether your instance type selection is cost-effective and identify opportunities to switch to more economical instance families.',
            values=['percent', 'value']
          ),

        nodeTable:
          dashboards.tablePanel(
            'Nodes Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.nodeMonthlyCpuCost,
              },
              {
                expr: queries.nodeMonthlyRamCost,
              },
              {
                expr: queries.nodeTotalCost,
              },
            ],
            description='Detailed breakdown of monthly costs per node, showing CPU cost, RAM cost, and total cost for each node along with instance type and architecture. Sorted by total cost to highlight the most expensive nodes. Use this to identify underutilized expensive nodes that could be downsized or removed.',
            sortBy={
              name: 'Total Cost',
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
                    node: 'Node',
                    instance_type: 'Instance Type',
                    arch: 'Architecture',
                    'Value #A': 'CPU Cost',
                    'Value #B': 'RAM Cost',
                    'Value #C': 'Total Cost',
                  },
                  indexByName: {
                    node: 0,
                    instance_type: 1,
                    arch: 2,
                    'Value #A': 3,
                    'Value #B': 4,
                    'Value #C': 5,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ]
          ),

        pvTable:
          dashboards.tablePanel(
            'Persistent Volumes Monthly Cost',
            'decgbytes',
            [
              {
                expr: queries.pvTotalGib,
              },
              {
                expr: queries.pvMonthlyCost,
              },
            ],
            description='List of all Persistent Volumes with their capacity (in GiB) and monthly cost, sorted by total cost. Use this to identify large or expensive volumes that may be candidates for cleanup, resizing, or migration to cheaper storage classes.',
            sortBy={
              name: 'Total Cost',
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

        namespaceTable:
          dashboards.tablePanel(
            'Namespace Monthly Cost',
            'currencyUSD',
            [
              {
                expr: queries.namespaceMonthlyCost,
              },
              {
                expr: queries.costDifference7d,
              },
              {
                expr: queries.costDifference7d,
              },
            ],
            description='Top 10 namespaces by current monthly cost with percentage change compared to 7 days and 30 days ago. Positive percentages indicate cost increases (red), negative percentages indicate cost decreases (green). Click on a namespace name to drill down into detailed pod and container costs. Use this to track namespace-level spending trends and identify teams or applications with growing costs.',
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
                    namespace: 'Namespace',
                    'Value #A': 'Monthly Cost',
                    'Value #B': 'Cost Change vs 7d Ago (%)',
                    'Value #C': 'Cost Change vs 30d Ago (%)',
                  },
                  indexByName: {
                    namespace: 0,
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
              tbOverride.byName.new('Namespace') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withLinks(
                  tbPanelOptions.link.withTitle('Go To Namespace') +
                  tbPanelOptions.link.withType('dashboard') +
                  tbPanelOptions.link.withUrl(
                    '/d/%s/opencost-namespace?var-job=$job&var-namespace=${__data.fields.Namespace}' % $._config.dashboardIds['opencost-namespace']
                  ) +
                  tbPanelOptions.link.withTargetBlank(true)
                )
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
      };

      local rows =
        [
          row.new('Cluster Summary') +
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
            panels.hourCostTimeSeries,
            panels.dailyCostTimeSeries,
            panels.monthlyCostTimeSeries,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=5
        ) +
        grid.wrapPanels(
          [
            panels.resourceCostPieChartPanel,
            panels.namespaceCostPieChartPanel,
            panels.instanceTypeCostPieChartPanel,
          ],
          panelWidth=8,
          panelHeight=5,
          startY=10
        ) +
        grid.wrapPanels(
          [
            panels.totalCostVarianceTimeSeries,
            panels.resourceCostVarianceTimeSeries,
          ],
          panelWidth=12,
          panelHeight=5,
          startY=15
        ) +
        [
          row.new('Cloud Resources') +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        [
          panels.nodeTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(16) +
          tablePanel.gridPos.withH(10),
          panels.pvTable +
          tablePanel.gridPos.withX(16) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(8) +
          tablePanel.gridPos.withH(10),
          row.new('Namespace Summary') +
          row.gridPos.withX(0) +
          row.gridPos.withY(31) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.namespaceTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(32) +
          tablePanel.gridPos.withW(24) +
          tablePanel.gridPos.withH(12),
        ];

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'OpenCost / Overview',
      ) +
      dashboard.withDescription('A comprehensive overview dashboard for OpenCost that displays cluster-wide cost metrics including hourly, daily, and monthly costs broken down by resource type (CPU, RAM, PV), instance type, namespace, and individual nodes. Use this dashboard to monitor overall infrastructure spending, identify cost trends, and detect cost anomalies across your Kubernetes cluster. %s' % mixinUtils.dashboards.dashboardDescriptionLink('opencost-mixin', 'https://github.com/adinhodovic/opencost-mixin')) +
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
