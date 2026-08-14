// ============================================================
// Public Transport Inequality Explorer
// main.js
// Current step: D3 map + ranking bar chart
// ============================================================


// ------------------------------------------------------------
// Global data containers
// ------------------------------------------------------------

let boundaryData = null;
let metricsData = null;


// ------------------------------------------------------------
// Dashboard state
// ------------------------------------------------------------

const state = {
  region: "All",
  mode: "All",
  metric: "overall_score",
  topN: 10,

  selectedLga: null,
  selectedLgas: [],

  // Preserve user map zoom/pan after linked-view updates.
  mapTransform: d3.zoomIdentity
};


// ------------------------------------------------------------
// Metric labels for UI and tooltip
// ------------------------------------------------------------

const metricLabels = {
  overall_score: "Overall inequality score",
  coverage_gap: "Coverage gap",
  frequency_gap: "Frequency gap",
  service_gap: "Service gap",
  weekend_weekday_gap: "Weekend-weekday gap",
  mode_diversity_gap: "Mode diversity gap"
};

const chartColors = {
  rankingBar: "#4f6f8f",
  rankingBarHover: "#6f5bd8",
  rankingBarMuted: "#aab6c5"
};

// ------------------------------------------------------------
// Non-standard geography records excluded from the D3 view
// ------------------------------------------------------------

const excludedLgaNames = new Set([
  "Migratory - Offshore - Shipping (Vic.)",
  "No usual address (Vic.)",
  "Unincorporated Vic"
]);

// ------------------------------------------------------------
// Region classification for front-end filtering
// ------------------------------------------------------------
// This is a design-level grouping for the D3 interface.
// Names are normalised before matching to avoid small naming
// differences such as extra spaces or parenthesised suffixes.

// ------------------------------------------------------------
// Region classification for front-end filtering
// ------------------------------------------------------------
// The source LGA names sometimes include suffixes such as "(Vic.)".
// We normalise names before matching so "Bayside (Vic.)" becomes "bayside".

function normaliseLgaName(name) {
  return String(name)
    .trim()
    .replace(/\s*\(vic\.\)\s*$/i, "")
    .replace(/\s*\([^)]*\)\s*$/g, "")
    .replace(/\s+/g, " ")
    .toLowerCase();
}

const innerMelbourneLgaNames = [
  "Boroondara",
  "Darebin",
  "Glen Eira",
  "Hobsons Bay",
  "Maribyrnong",
  "Melbourne",
  "Merri-bek",
  "Moonee Valley",
  "Port Phillip",
  "Stonnington",
  "Yarra"
];

const outerMelbourneLgaNames = [
  "Banyule",
  "Bayside",
  "Brimbank",
  "Cardinia",
  "Casey",
  "Frankston",
  "Greater Dandenong",
  "Hume",
  "Kingston",
  "Knox",
  "Manningham",
  "Maroondah",
  "Melton",
  "Monash",
  "Mornington Peninsula",
  "Nillumbik",
  "Whitehorse",
  "Whittlesea",
  "Wyndham",
  "Yarra Ranges"
];

const innerMelbourneLgas = new Set(
  innerMelbourneLgaNames.map(normaliseLgaName)
);

const outerMelbourneLgas = new Set(
  outerMelbourneLgaNames.map(normaliseLgaName)
);

function getRegionType(lgaName) {
  const cleanName = normaliseLgaName(lgaName);

  if (innerMelbourneLgas.has(cleanName)) {
    return "Inner Melbourne";
  }

  if (outerMelbourneLgas.has(cleanName)) {
    return "Outer Melbourne";
  }

  return "Regional Victoria";
}

function getMetricRegionType(d) {
  return d.region_type || getRegionType(d.lga_name);
}

function regionMatches(d) {
  return state.region === "All" || getMetricRegionType(d) === state.region;
}

// ------------------------------------------------------------
// Helper: convert CSV values to numbers safely
// ------------------------------------------------------------

function toNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const number = +value;
  return Number.isFinite(number) ? number : null;
}


// ------------------------------------------------------------
// Parse each row of lga_metrics.csv
// ------------------------------------------------------------

function parseMetricRow(d) {
  return {
    lga_code: String(d.lga_code),
    lga_name: d.lga_name,
    area_sqkm: toNumber(d.area_sqkm),
    mode: d.mode,

    has_service:
      d.has_service === "TRUE" ||
      d.has_service === "true" ||
      d.has_service === true,

    mode_count: toNumber(d.mode_count),

    n_stops: toNumber(d.n_stops),
    n_routes: toNumber(d.n_routes),
    n_trips: toNumber(d.n_trips),
    n_stop_events: toNumber(d.n_stop_events),
    weekday_stop_events: toNumber(d.weekday_stop_events),
    weekend_stop_events: toNumber(d.weekend_stop_events),

    first_service_hour: toNumber(d.first_service_hour),
    last_service_hour: toNumber(d.last_service_hour),
    service_span_hours: toNumber(d.service_span_hours),

    stop_density: toNumber(d.stop_density),
    route_density: toNumber(d.route_density),
    events_per_stop: toNumber(d.events_per_stop),
    weekend_weekday_ratio: toNumber(d.weekend_weekday_ratio),

    coverage_gap: toNumber(d.coverage_gap),
    frequency_gap: toNumber(d.frequency_gap),
    service_gap: toNumber(d.service_gap),
    weekend_weekday_gap: toNumber(d.weekend_weekday_gap),
    mode_diversity_gap: toNumber(d.mode_diversity_gap),
    overall_score: toNumber(d.overall_score)
  };
}


// ------------------------------------------------------------
// Load data
// ------------------------------------------------------------

Promise.all([
  d3.json("data/processed/vic_lga_2025_simplified.geojson"),
  d3.csv("data/processed/lga_metrics.csv", parseMetricRow)
])
  .then(([boundaries, metrics]) => {
    // Remove non-standard geography records from GeoJSON.
    boundaryData = {
        ...boundaries,
        features: boundaries.features
        .filter(feature => {
            const lgaName = getFeatureName(feature);
            return !excludedLgaNames.has(lgaName);
        })
        .map(feature => {
            const lgaName = getFeatureName(feature);

            return {
                ...feature,
                properties: {
                    ...feature.properties,
                    region_type: getRegionType(lgaName)
                }
            };
        })
    };
    metricsData = metrics
      .filter(d => {
        return !excludedLgaNames.has(d.lga_name);
      })
      .map(d => {
        return{
            ...d,
            region_type: getRegionType(d.lga_name)
        };
      });

    // Remove the same records from the metrics table.
    metricsData = metrics.filter(d => {
      return !excludedLgaNames.has(d.lga_name);
    });

    console.log("Data loaded successfully.");
    console.log("Boundary features:", boundaryData.features.length);
    console.log("Metric rows:", metricsData.length);
    console.log("GeoJSON bounds:", d3.geoBounds(boundaryData));
    console.table(
        d3.rollups(
            metricsData.filter(d => d.mode === "All"),
            v => v.length,
            d => d.region_type
        ).map(d => {
            return {
                region_type: d[0],
                lgas: d[1]
            };
        })
    );

    initialiseControls();
    updateAll();
  })
  .catch(error => {
    console.error("Data loading failed:", error);

    d3.select("#map").html(`
      <div class="placeholder-note">
        Data loading failed. Check file names and paths in data/processed.
      </div>
    `);

    d3.select("#ranking-bar").html(`
      <div class="placeholder-note">
        Data loading failed. Check file names and paths in data/processed.
      </div>
    `);
  });


// ------------------------------------------------------------
// Initialise control panel events
// ------------------------------------------------------------

function initialiseControls() {
  d3.select("#region-select").on("change", function () {
    state.region = d3.select(this).property("value");
    state.mapTransform = d3.zoomIdentity;
    clearSelectedLgas();
    updateAll();

    // Region filter can be connected later if region_type is added to CSV.
    updateAll();
  });

  d3.select("#mode-select").on("change", function () {
    state.mode = d3.select(this).property("value");
    clearSelectedLgas();
    updateAll();
  });

  d3.select("#metric-select").on("change", function () {
    state.metric = d3.select(this).property("value");
    updateAll();
  });

  d3.select("#topn-select").on("change", function () {
    state.topN = +d3.select(this).property("value");
    updateAll();
  });

  d3.select("#reset-button").on("click", function () {
    state.region = "All";
    state.mode = "All";
    state.metric = "overall_score";
    state.topN = 10;
    state.mapTransform = d3.zoomIdentity;
    clearSelectedLgas();

    d3.select("#region-select").property("value", state.region);
    d3.select("#mode-select").property("value", state.mode);
    d3.select("#metric-select").property("value", state.metric);
    d3.select("#topn-select").property("value", String(state.topN));

    updateAll();
  });

  window.addEventListener("resize", updateAll);
}


// ------------------------------------------------------------
// Main update function
// ------------------------------------------------------------

function updateAll(options = {}) {
  if (!boundaryData || !metricsData) {
    return;
  }

  if (!options.skipMap) {
    renderMap();
  }

  renderRankingBar();
  renderLgaProfile();
  renderBubbleChart();
  renderServiceSpan();
  renderDumbbellChart();
  renderConclusionMatrix();
}


// ------------------------------------------------------------
// Get current metrics based on selected mode
// ------------------------------------------------------------

function getCurrentMetrics() {
  return metricsData.filter(d => {
    return d.mode === state.mode && regionMatches(d);
  });
}

function featureRegionMatches(feature) {
  const featureRegion =
    feature.properties.region_type || getRegionType(getFeatureName(feature));

  return state.region === "All" || featureRegion === state.region;
}


function getVisibleBoundaryData() {
  if (!boundaryData) {
    return null;
  }

  if (state.region === "All") {
    return boundaryData;
  }

  const filteredFeatures = boundaryData.features.filter(featureRegionMatches);

  return {
    ...boundaryData,
    features: filteredFeatures
  };
}

// ------------------------------------------------------------
// Get top N data for ranking chart
// ------------------------------------------------------------

function getTopMetrics() {
  const currentMetrics = getCurrentMetrics();

  return currentMetrics
    .filter(d => Number.isFinite(d[state.metric]))
    .sort((a, b) => d3.descending(a[state.metric], b[state.metric]))
    .slice(0, state.topN);
}

// ------------------------------------------------------------
// Selection helpers
// ------------------------------------------------------------
// selectedLga = primary LGA, usually the most recently clicked.
// selectedLgas = comparison list, up to 3 LGAs.

function isSelectedLga(lgaCode) {
  return state.selectedLgas.includes(String(lgaCode));
}

function getSelectionIndex(lgaCode) {
  return state.selectedLgas.indexOf(String(lgaCode));
}

const comparisonColors = [
  "#6f5bd8",
  "#00a896",
  "#f2a51a"
];

function getSelectionColor(lgaCode) {
  const index = getSelectionIndex(lgaCode);

  if (index < 0) {
    return null;
  }

  return comparisonColors[index % comparisonColors.length];
}

function toggleSelectedLga(lgaCode) {
  const code = String(lgaCode);
  const index = state.selectedLgas.indexOf(code);

  // If the LGA is already selected, remove it.
  if (index >= 0) {
    state.selectedLgas.splice(index, 1);

    // If we removed the primary LGA, make the latest remaining one primary.
    if (state.selectedLga === code) {
      state.selectedLga = state.selectedLgas[state.selectedLgas.length - 1] || null;
    }

    return;
  }

  // If there are already 3 selected LGAs, remove the oldest one.
  if (state.selectedLgas.length >= 3) {
    state.selectedLgas.shift();
  }

  // Add the new LGA and make it the primary selected LGA.
  state.selectedLgas.push(code);
  state.selectedLga = code;
}

function clearSelectedLgas() {
  state.selectedLga = null;
  state.selectedLgas = [];
}

// ------------------------------------------------------------
// GeoJSON property helpers
// ------------------------------------------------------------

function getFeatureCode(feature) {
  return String(
    feature.properties.lga_code ??
    feature.properties.LGA_CODE25 ??
    feature.properties.LGA_CODE21
  );
}


function getFeatureName(feature) {
  return (
    feature.properties.lga_name ??
    feature.properties.LGA_NAME25 ??
    feature.properties.LGA_NAME21 ??
    "Unknown LGA"
  );
}


// ------------------------------------------------------------
// Tooltip helpers
// ------------------------------------------------------------

function showTooltip(event, html) {
  d3.select("#tooltip")
    .classed("hidden", false)
    .html(html)
    .style("left", `${event.pageX + 14}px`)
    .style("top", `${event.pageY + 14}px`);
}


function moveTooltip(event) {
  d3.select("#tooltip")
    .style("left", `${event.pageX + 14}px`)
    .style("top", `${event.pageY + 14}px`);
}


function hideTooltip() {
  d3.select("#tooltip")
    .classed("hidden", true);
}


// ------------------------------------------------------------
// Format helpers
// ------------------------------------------------------------

function formatNumber(value, digits = 1) {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return "No data";
  }

  return d3.format(`.${digits}f`)(value);
}


function formatInteger(value) {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return "No data";
  }

  return d3.format(",")(value);
}


function truncateText(text, maxLength = 22) {
  if (!text) {
    return "";
  }

  return text.length > maxLength
    ? text.slice(0, maxLength - 1) + "…"
    : text;
}

function formatHour(value) {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return "No service";
  }

  const totalMinutes = Math.round(value * 60);
  const dayOffset = Math.floor(totalMinutes / (24 * 60));
  const minutesInDay = totalMinutes % (24 * 60);

  const hour = Math.floor(minutesInDay / 60);
  const minute = minutesInDay % 60;

  const timeText = `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;

  return dayOffset > 0 ? `${timeText} +${dayOffset}d` : timeText;
}


function getMetricRowByLgaAndMode(lgaCode, mode) {
  return metricsData.find(d => {
    return d.lga_code === String(lgaCode) && d.mode === mode;
  });
}

function getSelectedRowsForCurrentMode() {
  return state.selectedLgas
    .map(code => getMetricRowByLgaAndMode(code, state.mode))
    .filter(Boolean);
}

// ============================================================
// MAP
// ============================================================

function updateMapSelectionStyles() {
  const currentMetrics = getCurrentMetrics();

  const metricByLga = new Map(
    currentMetrics.map(d => [d.lga_code, d])
  );

  d3.selectAll("#map .lga-path")
    .attr("stroke", feature => {
      const lgaCode = getFeatureCode(feature);

      return isSelectedLga(lgaCode)
        ? getSelectionColor(lgaCode) || "#171717"
        : "rgba(23, 23, 23, 0.45)";
    })
    .attr("stroke-width", feature => {
      const lgaCode = getFeatureCode(feature);
      return isSelectedLga(lgaCode) ? 3 : 0.65;
    })
    .attr("opacity", feature => {
      const lgaCode = getFeatureCode(feature);
      const isInRegion = metricByLga.has(lgaCode);

      if (!isInRegion) {
        return 0.16;
      }

      if (state.selectedLgas.length === 0) {
        return 1;
      }

      return isSelectedLga(lgaCode) ? 1 : 0.42;
    });
}

function renderMap() {
  const container = d3.select("#map");

  container.html("");

  const node = container.node();
  const width = node.clientWidth;
  const height = node.clientHeight;

  if (width === 0 || height === 0) {
    console.warn("Map container has zero width or height.");
    return;
  }

  const currentMetrics = getCurrentMetrics();

  const modeMetrics = metricsData.filter(d => d.mode === state.mode);

  const metricByLga = new Map(
    currentMetrics.map(d => [d.lga_code, d])
  );

  const allModeMetricByLga = new Map(
    modeMetrics.map(d => [d.lga_code, d])
  );

  const values = currentMetrics
    .map(d => d[state.metric])
    .filter(d => Number.isFinite(d));

  const [minValue, maxValue] = d3.extent(values);

  const metricLabel = metricLabels[state.metric] || state.metric;

  const colorScale = d3.scaleSequential()
    .domain([minValue, maxValue])
    .interpolator(d3.interpolateRgb("#fff7ed", "#ff5a3d"));

  const svg = container
    .append("svg")
    .attr("class", "map-svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("role", "img")
    .attr(
      "aria-label",
      "Choropleth map of public transport inequality across Victorian LGAs"
    );

  // ------------------------------------------------------------
  // Fit map to selected region
  // ------------------------------------------------------------
  // The full boundaryData is still drawn, but the projection is fitted
  // to the currently selected region. This means Inner Melbourne,
  // Outer Melbourne, and Regional Victoria each get a better initial view.
  // ------------------------------------------------------------

  const visibleBoundaryData = getVisibleBoundaryData();

  const fitData =
    visibleBoundaryData && visibleBoundaryData.features.length > 0
      ? visibleBoundaryData
      : boundaryData;

  const mapPadding = state.region === "All" ? 26 : 42;

  const projection = d3.geoIdentity()
    .reflectY(true)
    .fitExtent(
      [
        [mapPadding, mapPadding],
        [width - mapPadding, height - mapPadding]
      ],
      fitData
    );

  const path = d3.geoPath()
    .projection(projection);

  // This group is what we zoom and pan.
  // The legend stays outside this group, so it will not zoom.
  const zoomLayer = svg
    .append("g")
    .attr("class", "map-zoom-layer");

  const lgaLayer = zoomLayer
    .append("g")
    .attr("class", "lga-layer");

  lgaLayer
    .selectAll("path")
    .data(boundaryData.features)
    .join("path")
    .attr("class", "lga-path")
    .attr("d", path)
    .attr("fill", feature => {
      const lgaCode = getFeatureCode(feature);
      const row = metricByLga.get(lgaCode);

      if (!row || !Number.isFinite(row[state.metric])) {
        return "#e6dfd6";
      }

      return colorScale(row[state.metric]);
    })
    .attr("stroke", feature => {
      const lgaCode = getFeatureCode(feature);

      return isSelectedLga(lgaCode)
        ? getSelectionColor(lgaCode) || "#171717"
        : "rgba(23, 23, 23, 0.45)";
    })
    .attr("stroke-width", feature => {
      const lgaCode = getFeatureCode(feature);

      return isSelectedLga(lgaCode) ? 2.8 : 0.65;
    })
    .attr("opacity", feature => {
      const lgaCode = getFeatureCode(feature);
      const isInRegion = metricByLga.has(lgaCode);

      if (!isInRegion) {
        return 0.16;
      }

      if (state.selectedLgas.length === 0) {
        return 1;
      }

      return isSelectedLga(lgaCode) ? 1 : 0.5;
    })
    .on("mouseenter", function (event, feature) {
      const lgaCode = getFeatureCode(feature);
      const lgaName = getFeatureName(feature);
      const row = metricByLga.get(lgaCode);
      const fullModeRow = allModeMetricByLga.get(lgaCode);

      d3.select(this)
        .attr(
          "stroke", 
          isSelectedLga(lgaCode)
            ? getSelectionColor(lgaCode) || "#171717"
            : "#171717"
        )
        .attr("stroke-width", isSelectedLga(lgaCode) ? 3 : 0.65);

      if (!row) {
        showTooltip(event, `
          <strong>${lgaName}</strong><br>
          ${fullModeRow ? `Region: ${getMetricRegionType(fullModeRow)}<br>` : ""}
          Not included in current region filter.
        `);
        return;
      }

      showTooltip(event, `
        <strong>${row.lga_name}</strong><br>
        Region: ${getMetricRegionType(row)}<br>
        Mode: ${state.mode}<br>
        ${metricLabel}: ${formatNumber(row[state.metric], 1)}<br>
        Stops: ${formatInteger(row.n_stops)}<br>
        Routes: ${formatInteger(row.n_routes)}<br>
        Has service: ${row.has_service ? "Yes" : "No"}
      `);
    })
    .on("mousemove", function (event) {
      moveTooltip(event);
    })
    .on("mouseleave", function (event, feature) {
      const lgaCode = getFeatureCode(feature);

      d3.select(this)
        .attr(
          "stroke",
          isSelectedLga(lgaCode)
            ? "#171717"
            : "rgba(23, 23, 23, 0.45)"
        )
        .attr("stroke-width", isSelectedLga(lgaCode) ? 2.8 : 0.65);

      hideTooltip();
    })
    .on("click", function (event, feature) {
      const lgaCode = getFeatureCode(feature);

      if (!metricByLga.has(lgaCode)) {
        return;
      }

      toggleSelectedLga(lgaCode);
      updateMapSelectionStyles();
      updateAll({ skipMap: true });
    });

  // ------------------------------------------------------------
  // D3 zoom behaviour
  // ------------------------------------------------------------
  // Mouse wheel = zoom in / out
  // Drag = pan
  // This uses D3 itself, not Leaflet or MapBox.
  // ------------------------------------------------------------

  const zoom = d3.zoom()
    .scaleExtent([1, 12])
    .translateExtent([
      [-width * 2, -height * 2],
      [width * 3, height * 3]
    ])
    .on("zoom", function (event) {
      state.mapTransform = event.transform;
      zoomLayer.attr("transform", event.transform);
    });

  svg.call(zoom);

  renderMapLegend(container, minValue, maxValue, metricLabel);
}


// ------------------------------------------------------------
// Render map legend
// ------------------------------------------------------------

function renderMapLegend(container, minValue, maxValue, metricLabel) {
  container
    .append("div")
    .attr("class", "map-legend")
    .html(`
      <div class="legend-title">${metricLabel}</div>
      <div class="legend-gradient"></div>
      <div class="legend-scale">
        <span>${formatNumber(minValue, 0)}</span>
        <span>${formatNumber(maxValue, 0)}</span>
      </div>
      <div class="legend-note">Darker colour = higher gap</div>
    `);
}


// ============================================================
// RANKING BAR CHART
// ============================================================

function renderRankingBar() {
  const container = d3.select("#ranking-bar");

  container.html("");

  const node = container.node();
  const width = node.clientWidth;
  const height = node.clientHeight;

  if (width === 0 || height === 0) {
    console.warn("Ranking container has zero width or height.");
    return;
  }

  const topData = getTopMetrics();
  const metricLabel = metricLabels[state.metric] || state.metric;

  // Ranking chart colour system.
  // These colours are local to this function to avoid accidental conflicts.
  const rankingBarColor = "#4f6f8f";
  const rankingBarHoverColor = "#6d86a3";
  const rankingBarMutedColor = "#8aa0b8";
  const rankingBarSelectedFallback = "#6f5bd8";

  function getRankingBarFill(d) {
    if (isSelectedLga(d.lga_code)) {
      return getSelectionColor(d.lga_code) || rankingBarSelectedFallback;
    }

    return rankingBarColor;
  }

  if (topData.length === 0) {
    container.html(`
      <div class="placeholder-note">
        No ranking data available for this selection.
      </div>
    `);
    return;
  }

  const margin = {
    top: 24,
    right: 54,
    bottom: 34,
    left: 148
  };

  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;

  const maxValue = d3.max(topData, d => d[state.metric]) || 100;

  const xScale = d3.scaleLinear()
    .domain([0, maxValue])
    .nice()
    .range([0, innerWidth]);

  const yScale = d3.scaleBand()
    .domain(topData.map(d => d.lga_name))
    .range([0, innerHeight])
    .padding(0.22);

  const svg = container
    .append("svg")
    .attr("class", "ranking-svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("role", "img")
    .attr("aria-label", "Horizontal bar chart of most underserved LGAs");

  const chart = svg
    .append("g")
    .attr("transform", `translate(${margin.left}, ${margin.top})`);

  // Background gridlines
  const xAxisGrid = d3.axisBottom(xScale)
    .ticks(4)
    .tickSize(-innerHeight)
    .tickFormat("");

  chart.append("g")
    .attr("class", "ranking-grid")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xAxisGrid);

  // Y labels
  chart.append("g")
    .attr("class", "ranking-y-axis")
    .selectAll("text")
    .data(topData)
    .join("text")
    .attr("x", -12)
    .attr("y", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("dy", "0.35em")
    .attr("text-anchor", "end")
    .text(d => truncateText(d.lga_name, 21));

  // Bars
  chart.append("g")
    .attr("class", "ranking-bars")
    .selectAll("rect")
    .data(topData, d => d.lga_code)
    .join("rect")
    .attr("class", "ranking-bar")
    .attr("x", 0)
    .attr("y", d => yScale(d.lga_name))
    .attr("height", yScale.bandwidth())
    .attr("width", d => xScale(d[state.metric]))
    .attr("rx", 7)
    .style("fill", d => getRankingBarFill(d))
    .attr("opacity", 1)
    .attr("stroke", d => {
      return isSelectedLga(d.lga_code) ? "#171717" : "none";
    })
    .attr("stroke-width", d => {
      return isSelectedLga(d.lga_code) ? 2 : 0;
    })
    .on("mouseenter", function (event, d) {
      d3.select(this)
        .style(
          "fill",
          isSelectedLga(d.lga_code)
            ? getRankingBarFill(d)
            : rankingBarHoverColor
        )
        .attr("opacity", 1);

      showTooltip(event, `
        <strong>${d.lga_name}</strong><br>
        Region: ${getMetricRegionType(d)}<br>
        Mode: ${state.mode}<br>
        ${metricLabel}: ${formatNumber(d[state.metric], 1)}<br>
        Overall score: ${formatNumber(d.overall_score, 1)}<br>
        Stops: ${formatInteger(d.n_stops)}<br>
        Routes: ${formatInteger(d.n_routes)}
      `);
    })
    .on("mousemove", function (event) {
      moveTooltip(event);
    })
    .on("mouseleave", function (event, d) {
      d3.select(this)
        .style("fill", getRankingBarFill(d))
        .attr("opacity", 1);

      hideTooltip();
    })
    .on("click", function (event, d) {
      toggleSelectedLga(d.lga_code);
      updateMapSelectionStyles();
      updateAll({ skipMap: true });
    });

  // Value labels
  chart.append("g")
    .attr("class", "ranking-value-labels")
    .selectAll("text")
    .data(topData, d => d.lga_code)
    .join("text")
    .attr("x", d => xScale(d[state.metric]) + 7)
    .attr("y", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("dy", "0.35em")
    .text(d => formatNumber(d[state.metric], 1));

  // X axis
  const xAxis = d3.axisBottom(xScale)
    .ticks(4)
    .tickSizeOuter(0);

  chart.append("g")
    .attr("class", "ranking-x-axis")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xAxis);

  // Axis label
  chart.append("text")
    .attr("class", "ranking-axis-label")
    .attr("x", innerWidth)
    .attr("y", innerHeight + 30)
    .attr("text-anchor", "end")
    .text(metricLabel);

  // Small note
  svg.append("text")
    .attr("class", "ranking-note")
    .attr("x", width - 16)
    .attr("y", 16)
    .attr("text-anchor", "end")
    .text(`Top ${state.topN} · ${state.mode}`);
}

// ============================================================
// SELECTED LGA PROFILE
// ============================================================

function renderLgaProfile() {
  const container = d3.select("#lga-profile");

  container.html("");

  const selectedRows = getSelectedRowsForCurrentMode();

  if (selectedRows.length === 0){
    container
      .append("div")
      .attr("class", "profile-empty")
      .html(`
        <p class="profile-empty-title">Select up to three LGAs to inspect or compare.</p>
        <p> 
          Click a local government area on the map or a bar in the ranking chart.
          Selecting two or three areas will turn this panel into a comparison view.
        </p>
      `);
    return;
  }

  if (selectedRows.length >= 2){
    renderInequalityComparison(container, selectedRows);
    return;
  }

  const row = selectedRows[0];
  const allModeRow = getMetricRowByLgaAndMode(row.lga_code, "All");

  if (!row) {
    container
      .append("div")
      .attr("class", "profile-empty")
      .html(`
        <p class="profile-empty-title">No data available for this LGA.</p>
        <p>
          The selected area does not have a matching row for the current mode.
        </p>
      `);

    return;
  }

  const metricItems = [
    {
      key: "coverage_gap",
      label: "Coverage gap",
      value: row.coverage_gap,
      explanation: "Based on stop density across the LGA."
    },
    {
      key: "frequency_gap",
      label: "Frequency gap",
      value: row.frequency_gap,
      explanation: "Based on average stop events per stop."
    },
    {
      key: "service_gap",
      label: "Service span gap",
      value: row.service_gap,
      explanation: "Based on first-to-last service span."
    },
    {
      key: "weekend_weekday_gap",
      label: "Weekend gap",
      value: row.weekend_weekday_gap,
      explanation: "Based on weekend service relative to weekday service."
    },
    {
      key: "mode_diversity_gap",
      label: "Mode diversity gap",
      value: row.mode_diversity_gap,
      explanation: "Based on available Bus / Train / Tram choices."
    }
  ];

  const profile = container
    .append("div")
    .attr("class", "lga-profile-panel");

  profile
    .append("div")
    .attr("class", "profile-topline")
    .html(`
      <div>
        <p class="profile-kicker">Selected LGA</p>
        <h4>${row.lga_name}</h4>
      </div>
      <div class="profile-score">
        <span>${formatNumber(row.overall_score, 1)}</span>
        <small>${state.mode} score</small>
      </div>
    `);

  profile
    .append("p")
    .attr("class", "profile-summary")
    .html(`
      Under the <strong>${state.mode}</strong> lens, this area has
      <strong>${formatInteger(row.n_stops)}</strong> stops,
      <strong>${formatInteger(row.n_routes)}</strong> routes, and
      <strong>${formatInteger(row.n_stop_events)}</strong> GTFS stop events.
    `);

  const stats = profile
    .append("div")
    .attr("class", "profile-stat-grid");

  const statItems = [
    {
      label: "First service",
      value: formatHour(row.first_service_hour)
    },
    {
      label: "Last service",
      value: formatHour(row.last_service_hour)
    },
    {
      label: "Service span",
      value: `${formatNumber(row.service_span_hours, 1)} hrs`
    },
    {
      label: "Modes available",
      value: `${row.mode_count} / 3`
    }
  ];

  stats
    .selectAll(".profile-stat")
    .data(statItems)
    .join("div")
    .attr("class", "profile-stat")
    .html(d => `
      <span>${d.label}</span>
      <strong>${d.value}</strong>
    `);

  profile
    .append("div")
    .attr("class", "profile-divider");

  profile
    .append("p")
    .attr("class", "profile-section-title")
    .text("What is driving the score?");

  const gapList = profile
    .append("div")
    .attr("class", "gap-list");

  const gapRows = gapList
    .selectAll(".gap-row")
    .data(metricItems)
    .join("div")
    .attr("class", d => {
      return d.key === state.metric
        ? "gap-row gap-row-active"
        : "gap-row";
    });

  gapRows
    .append("div")
    .attr("class", "gap-row-header")
    .html(d => `
      <span>${d.label}</span>
      <strong>${formatNumber(d.value, 1)}</strong>
    `);

  gapRows
    .append("div")
    .attr("class", "gap-bar-track")
    .append("div")
    .attr("class", "gap-bar-fill")
    .style("width", d => `${Math.max(0, Math.min(100, d.value))}%`);

  gapRows
    .append("p")
    .attr("class", "gap-explanation")
    .text(d => d.explanation);

  profile
    .append("div")
    .attr("class", "profile-footer-note")
    .html(`
      Higher gap values indicate weaker service provision under the selected metric.
      ${allModeRow ? `The all-mode score for this LGA is <strong>${formatNumber(allModeRow.overall_score, 1)}</strong>.` : ""}
    `);
}

function renderInequalityComparison(container, rows) {
  const gapFields = [
    {
      key: "overall_score",
      label: "Overall inequality score"
    },
    {
      key: "coverage_gap",
      label: "Coverage gap"
    },
    {
      key: "frequency_gap",
      label: "Frequency gap"
    },
    {
      key: "service_gap",
      label: "Service span gap"
    },
    {
      key: "weekend_weekday_gap",
      label: "Weekend-weekday gap"
    },
    {
      key: "mode_diversity_gap",
      label: "Mode diversity gap"
    }
  ];

  const panel = container
    .append("div")
    .attr("class", "lga-profile-panel comparison-panel");

  panel
    .append("div")
    .attr("class", "profile-topline")
    .html(`
      <div>
        <p class="profile-kicker">Comparison view</p>
        <h4>${rows.length} selected LGAs</h4>
      </div>
      <div class="profile-score">
        <span>${state.mode}</span>
        <small>active mode</small>
      </div>
    `);

  panel
    .append("p")
    .attr("class", "profile-summary")
    .html(`
      This view compares the selected LGAs under the <strong>${state.mode}</strong> lens.
      Higher values indicate larger service inequality or weaker provision.
    `);

  const cards = panel
    .append("div")
    .attr("class", "profile-stat-grid");

  cards
    .selectAll(".profile-stat")
    .data(rows)
    .join("div")
    .attr("class", "profile-stat comparison-stat")
    .style("border-color", d => getSelectionColor(d.lga_code) || "#171717")
    .html(d => `
      <span style="color:${getSelectionColor(d.lga_code) || "#171717"}">
        ${d.lga_name}
      </span>
      <strong>${formatNumber(d.overall_score, 1)}</strong>
      <div class="matrix-small-note">
        ${formatInteger(d.n_stops)} stops ·
        ${formatInteger(d.n_routes)} routes ·
        ${formatInteger(d.n_stop_events)} stop events
      </div>
    `);

  panel
    .append("div")
    .attr("class", "profile-divider");

  panel
    .append("p")
    .attr("class", "profile-section-title")
    .text("Inequality drivers compared");

  const comparisonList = panel
    .append("div")
    .attr("class", "gap-list comparison-gap-list");

  gapFields.forEach(metric => {
    const metricBlock = comparisonList
      .append("div")
      .attr("class", metric.key === state.metric ? "gap-row gap-row-active" : "gap-row");

    metricBlock
      .append("div")
      .attr("class", "gap-row-header")
      .html(`
        <span>${metric.label}</span>
        <strong>${metric.key === state.metric ? "Current metric" : ""}</strong>
      `);

    rows.forEach(row => {
      const value = row[metric.key];
      const safeWidth = Math.max(0, Math.min(100, value || 0));
      const colour = getSelectionColor(row.lga_code) || "#171717";

      const line = metricBlock
        .append("div")
        .attr("class", "comparison-gap-line");

      line
        .append("div")
        .attr("class", "gap-row-header")
        .style("margin-bottom", "4px")
        .html(`
          <span style="color:${colour}">${row.lga_name}</span>
          <strong>${formatNumber(value, 1)}</strong>
        `);

      line
        .append("div")
        .attr("class", "gap-bar-track")
        .append("div")
        .attr("class", "gap-bar-fill")
        .style("width", `${safeWidth}%`)
        .style("background", colour);
    });
  });

  panel
    .append("div")
    .attr("class", "profile-footer-note")
    .html(`
      The colours match the selected LGAs in the map and ranking chart.
      Click a selected LGA again to remove it from the comparison.
    `);
}

// ============================================================
// BUBBLE CHART
// Coverage vs service intensity
// ============================================================

function renderBubbleChart() {
  const container = d3.select("#bubble-chart");

  container.html("");

  const node = container.node();
  const width = node.clientWidth;
  const height = node.clientHeight;

  if (width === 0 || height === 0) {
    console.warn("Bubble chart container has zero width or height.");
    return;
  }

  const currentMetrics = getCurrentMetrics();

  if (currentMetrics.length === 0) {
    container.html(`
      <div class="placeholder-note">
        No bubble chart data available for this selection.
      </div>
    `);
    return;
  }

  const metricLabel = metricLabels[state.metric] || state.metric;

  // Use log1p transformed values for positioning because service data is skewed.
  // Tooltip still shows the original values.
  const chartData = currentMetrics.map(d => {
    return {
      ...d,
      x_value: Math.log1p(Math.max(0, d.stop_density || 0)),
      y_value: Math.log1p(Math.max(0, d.events_per_stop || 0)),
      size_value: Math.max(0, d.n_stop_events || 0),
      colour_value: d[state.metric]
    };
  });

  const margin = {
    top: 34,
    right: 28,
    bottom: 62,
    left: 70
  };

  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;

  const xMax = d3.max(chartData, d => d.x_value) || 1;
  const yMax = d3.max(chartData, d => d.y_value) || 1;
  const sizeMax = d3.max(chartData, d => d.size_value) || 1;

  const xScale = d3.scaleLinear()
    .domain([0, xMax])
    .nice()
    .range([0, innerWidth]);

  const yScale = d3.scaleLinear()
    .domain([0, yMax])
    .nice()
    .range([innerHeight, 0]);

  const radiusScale = d3.scaleSqrt()
    .domain([0, sizeMax])
    .range([4, 20]);

  const colourExtent = d3.extent(
    chartData
      .map(d => d.colour_value)
      .filter(d => Number.isFinite(d))
  );

  const colourScale = d3.scaleSequential()
    .domain(colourExtent)
    .interpolator(d3.interpolateRgb("#00a896", "#ff5a3d"));

  const servedData = chartData.filter(d => d.has_service);

  const medianX = d3.median(servedData, d => d.x_value) || 0;
  const medianY = d3.median(servedData, d => d.y_value) || 0;

  const svg = container
    .append("svg")
    .attr("class", "bubble-svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("role", "img")
    .attr(
      "aria-label",
      "Bubble chart comparing stop density and service intensity across LGAs"
    );

  const chart = svg
    .append("g")
    .attr("transform", `translate(${margin.left}, ${margin.top})`);

  // Gridlines
  const xGrid = d3.axisBottom(xScale)
    .ticks(5)
    .tickSize(-innerHeight)
    .tickFormat("");

  const yGrid = d3.axisLeft(yScale)
    .ticks(5)
    .tickSize(-innerWidth)
    .tickFormat("");

  chart.append("g")
    .attr("class", "bubble-grid")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xGrid);

  chart.append("g")
    .attr("class", "bubble-grid")
    .call(yGrid);

  // Median reference lines
  chart.append("line")
    .attr("class", "bubble-median-line")
    .attr("x1", xScale(medianX))
    .attr("x2", xScale(medianX))
    .attr("y1", 0)
    .attr("y2", innerHeight);

  chart.append("line")
    .attr("class", "bubble-median-line")
    .attr("x1", 0)
    .attr("x2", innerWidth)
    .attr("y1", yScale(medianY))
    .attr("y2", yScale(medianY));

  // Draw larger bubbles first so smaller ones remain visible.
  chart.append("g")
    .attr("class", "bubble-layer")
    .selectAll("circle")
    .data(
      chartData
        .slice()
        .sort((a, b) => d3.descending(a.size_value, b.size_value)),
      d => d.lga_code
    )
    .join("circle")
    .attr("class", "bubble-point")
    .attr("cx", d => xScale(d.x_value))
    .attr("cy", d => yScale(d.y_value))
    .attr("r", d => {
      if (!d.has_service) {
        return 4;
      }

      return radiusScale(d.size_value);
    })
    .attr("fill", d => {
      if (isSelectedLga(d.lga_code)) {
        return getSelectionColor(d.lga_code);
      }

      if (!d.has_service || !Number.isFinite(d.colour_value)) {
        return "#d8d2c9";
      }

      return colourScale(d.colour_value);
    })
    .attr("stroke", d => {
      return isSelectedLga(d.lga_code)
        ? "#171717"
        : "rgba(23, 23, 23, 0.55)";
    })
    .attr("stroke-width", d => {
      return isSelectedLga(d.lga_code) ? 2.4 : 0.8;
    })
    .attr("opacity", d => {
      if (state.selectedLgas.length === 0) {
        return d.has_service ? 0.82 : 0.42;
      }

      return isSelectedLga(d.lga_code) ? 1 : 0.22;
    })
    .on("mouseenter", function (event, d) {
      d3.select(this)
        .attr("stroke", "#171717")
        .attr("stroke-width", 2.4)
        .attr("opacity", 1);

      showTooltip(event, `
        <strong>${d.lga_name}</strong><br>
        Region: ${getMetricRegionType(d)}<br>
        Mode: ${state.mode}<br>
        ${metricLabel}: ${formatNumber(d[state.metric], 1)}<br>
        Stop density: ${formatNumber(d.stop_density, 3)} per km²<br>
        Events per stop: ${formatNumber(d.events_per_stop, 1)}<br>
        Stop events: ${formatInteger(d.n_stop_events)}<br>
        Has service: ${d.has_service ? "Yes" : "No"}
      `);
    })
    .on("mousemove", function (event) {
      moveTooltip(event);
    })
    .on("mouseleave", function (event, d) {
      d3.select(this)
        .attr("fill", () => {
          if (isSelectedLga(d.lga_code)) {
            return getSelectionColor(d.lga_code);
          }

          if (!d.has_service || !Number.isFinite(d.colour_value)) {
            return "#d8d2c9";
          }

          return colourScale(d.colour_value);
        })
        .attr(
          "stroke",
          isSelectedLga(d.lga_code)
            ? "#171717"
            : "rgba(23, 23, 23, 0.55)"
        )
        .attr(
          "stroke-width",
          isSelectedLga(d.lga_code) ? 2.4 : 0.8
        )
        .attr("opacity", () => {
          if (state.selectedLgas.length === 0) {
            return d.has_service ? 0.82 : 0.42;
          }

          return isSelectedLga(d.lga_code) ? 1 : 0.22;
        });

      hideTooltip();
    })
    .on("click", function (event, d) {
      toggleSelectedLga(d.lga_code);
      updateMapSelectionStyles();
      updateAll({ skipMap: true });
    });

  // Axes
  const xAxis = d3.axisBottom(xScale)
    .ticks(5)
    .tickSizeOuter(0);

  const yAxis = d3.axisLeft(yScale)
    .ticks(5)
    .tickSizeOuter(0);

  chart.append("g")
    .attr("class", "bubble-axis")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xAxis);

  chart.append("g")
    .attr("class", "bubble-axis")
    .call(yAxis);

  // Axis labels
  chart.append("text")
    .attr("class", "bubble-axis-label")
    .attr("x", innerWidth)
    .attr("y", innerHeight + 44)
    .attr("text-anchor", "end")
    .text("Stop density, log transformed");

  chart.append("text")
    .attr("class", "bubble-axis-label")
    .attr("transform", "rotate(-90)")
    .attr("x", 0)
    .attr("y", -48)
    .attr("text-anchor", "end")
    .text("Events per stop, log transformed");

  // Short explanatory note
  svg.append("text")
    .attr("class", "bubble-note")
    .attr("x", width - 18)
    .attr("y", 18)
    .attr("text-anchor", "end")
    .text(`Colour = ${metricLabel}; size = stop events`);

  // Quadrant labels
  chart.append("text")
    .attr("class", "bubble-quadrant-label")
    .attr("x", innerWidth - 6)
    .attr("y", 14)
    .attr("text-anchor", "end")
    .text("High coverage / high intensity");

  chart.append("text")
    .attr("class", "bubble-quadrant-label")
    .attr("x", 6)
    .attr("y", innerHeight - 8)
    .attr("text-anchor", "start")
    .text("Low coverage / low intensity");
}

// ============================================================
// SERVICE SPAN BY MODE
// ============================================================

function renderServiceSpan() {
  const container = d3.select("#service-span");
  container.html("");

  if (state.selectedLgas.length === 0) {
    container
      .append("div")
      .attr("class", "service-empty")
      .html(`
        <p class="service-empty-title">Select one to three LGAs to see service span.</p>
        <p>
          Click LGAs on the map, ranking chart, or bubble chart.
          Each selected LGA will appear as its own service span block.
        </p>
      `);
    return;
  }

  const modes = ["Bus", "Train", "Tram"];

  const selectedAllRows = state.selectedLgas
    .map(lgaCode => getMetricRowByLgaAndMode(lgaCode, "All"))
    .filter(Boolean);

  // 外层容器：让多个 LGA block 垂直排列
  const stack = container
    .append("div")
    .attr("class", "service-span-stack");

  // 统一算一个 x 轴最大值，让不同 LGA 的图可比较
  const allServiceRows = state.selectedLgas.flatMap(lgaCode => {
    return modes.map(mode => getMetricRowByLgaAndMode(lgaCode, mode)).filter(Boolean);
  });

  const maxLastService = d3.max(
    allServiceRows
      .filter(d => d.has_service && Number.isFinite(d.last_service_hour))
      .map(d => d.last_service_hour)
  );

  const xMax = Math.max(24, maxLastService || 24);

  // 为每个 LGA 画一个独立 block
  selectedAllRows.forEach(allRow => {
    const lgaCode = allRow.lga_code;
    const lgaName = allRow.lga_name;
    const blockColour = getSelectionColor(lgaCode) || "#171717";

    const lgaRows = modes.map(mode => {
      const row = getMetricRowByLgaAndMode(lgaCode, mode);

      return {
        lga_code: String(lgaCode),
        lga_name: lgaName,
        mode,
        row,
        colour: blockColour,
        has_service: row ? row.has_service : false,
        first_service_hour: row ? row.first_service_hour : null,
        last_service_hour: row ? row.last_service_hour : null,
        service_span_hours: row ? row.service_span_hours : 0,
        n_stops: row ? row.n_stops : 0,
        n_routes: row ? row.n_routes : 0,
        n_stop_events: row ? row.n_stop_events : 0,
        overall_score: row ? row.overall_score : null
      };
    });

    const block = stack
      .append("div")
      .attr("class", "service-lga-block");

    block
      .append("div")
      .attr("class", "service-lga-block-header")
      .html(`
        <h4 style="color:${blockColour}">${lgaName}</h4>
        <p>First and last service time by mode</p>
      `);

    const svgWidth = container.node().clientWidth || 700;
    const width = Math.max(600, svgWidth - 8);
    const height = 230;

    const margin = {
      top: 20,
      right: 44,
      bottom: 46,
      left: 94
    };

    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const xScale = d3.scaleLinear()
      .domain([0, xMax])
      .range([0, innerWidth]);

    const yScale = d3.scaleBand()
      .domain(modes)
      .range([0, innerHeight])
      .padding(0.42);

    const svg = block
      .append("svg")
      .attr("class", "service-span-mini-svg")
      .attr("viewBox", `0 0 ${width} ${height}`);

    const chart = svg
      .append("g")
      .attr("transform", `translate(${margin.left}, ${margin.top})`);

    // 9pm reference
    const lateNightHour = 21;
    if (lateNightHour <= xMax) {
      chart.append("line")
        .attr("class", "service-reference-line")
        .attr("x1", xScale(lateNightHour))
        .attr("x2", xScale(lateNightHour))
        .attr("y1", -8)
        .attr("y2", innerHeight + 8);

      chart.append("text")
        .attr("class", "service-reference-label")
        .attr("x", xScale(lateNightHour) + 5)
        .attr("y", -10)
        .text("9pm reference");
    }

    // 背景轨道
    chart.append("g")
      .selectAll(".service-track")
      .data(lgaRows)
      .join("line")
      .attr("class", "service-track")
      .attr("x1", 0)
      .attr("x2", innerWidth)
      .attr("y1", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("y2", d => yScale(d.mode) + yScale.bandwidth() / 2);

    // service span line
    chart.append("g")
      .selectAll(".service-span-line")
      .data(lgaRows)
      .join("line")
      .attr("class", d => {
        return d.mode === state.mode
          ? "service-span-line service-span-line-active"
          : "service-span-line";
      })
      .attr("x1", d => {
        return d.has_service && Number.isFinite(d.first_service_hour)
          ? xScale(d.first_service_hour)
          : 0;
      })
      .attr("x2", d => {
        return d.has_service && Number.isFinite(d.last_service_hour)
          ? xScale(d.last_service_hour)
          : 0;
      })
      .attr("y1", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("y2", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .style("stroke", blockColour)
      .attr("opacity", d => d.has_service ? 1 : 0);

    // first dot
    chart.append("g")
      .selectAll(".service-start-dot")
      .data(lgaRows)
      .join("circle")
      .attr("class", "service-start-dot")
      .attr("cx", d => {
        return d.has_service && Number.isFinite(d.first_service_hour)
          ? xScale(d.first_service_hour)
          : 0;
      })
      .attr("cy", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("r", d => d.has_service ? 5.5 : 0)
      .style("fill", "#f8f1e8")
      .style("stroke", blockColour)
      .style("stroke-width", 2);

    // last dot
    chart.append("g")
      .selectAll(".service-end-dot")
      .data(lgaRows)
      .join("circle")
      .attr("class", "service-end-dot")
      .attr("cx", d => {
        return d.has_service && Number.isFinite(d.last_service_hour)
          ? xScale(d.last_service_hour)
          : 0;
      })
      .attr("cy", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("r", d => d.has_service ? 5.5 : 0)
      .style("fill", blockColour)
      .style("stroke", "#171717")
      .style("stroke-width", 1.2);

    // 左侧 mode label
    chart.append("g")
      .selectAll(".service-mode-label")
      .data(lgaRows)
      .join("text")
      .attr("class", "service-mode-label")
      .attr("x", -14)
      .attr("y", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("dy", "0.35em")
      .attr("text-anchor", "end")
      .text(d => d.mode);

    // no service
    chart.append("g")
      .selectAll(".service-no-data")
      .data(lgaRows.filter(d => !d.has_service))
      .join("text")
      .attr("class", "service-no-data")
      .attr("x", 0)
      .attr("y", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("dy", "0.35em")
      .text("No service recorded");

    // 时间标签
    chart.append("g")
      .selectAll(".service-time-label")
      .data(lgaRows.filter(d => d.has_service))
      .join("text")
      .attr("class", "service-time-label")
      .attr("x", d => Math.min(xScale(d.last_service_hour) + 8, innerWidth - 82))
      .attr("y", d => yScale(d.mode) + yScale.bandwidth() / 2)
      .attr("dy", "0.35em")
      .text(d => `${formatHour(d.first_service_hour)} – ${formatHour(d.last_service_hour)}`);

    // x axis
    const tickValues = [0, 6, 12, 18, 21, 24, 30].filter(d => d <= xMax);

    const xAxis = d3.axisBottom(xScale)
      .tickValues(tickValues)
      .tickFormat(d => formatHour(d))
      .tickSizeOuter(0);

    chart.append("g")
      .attr("class", "service-axis")
      .attr("transform", `translate(0, ${innerHeight})`)
      .call(xAxis);

    chart.append("text")
      .attr("class", "service-axis-label")
      .attr("x", innerWidth)
      .attr("y", innerHeight + 36)
      .attr("text-anchor", "end")
      .text("Time of day; values after 24:00 indicate after midnight");

    // hover layer
    chart.append("g")
      .selectAll(".service-hover-row")
      .data(lgaRows)
      .join("rect")
      .attr("class", "service-hover-row")
      .attr("x", 0)
      .attr("y", d => yScale(d.mode) - 8)
      .attr("width", innerWidth)
      .attr("height", yScale.bandwidth() + 16)
      .on("mouseenter", function (event, d) {
        if (!d.row) {
          showTooltip(event, `
            <strong>${d.lga_name}</strong><br>
            Mode: ${d.mode}<br>
            No data available.
          `);
          return;
        }

        showTooltip(event, `
          <strong>${d.lga_name}</strong><br>
          Mode: ${d.mode}<br>
          First service: ${formatHour(d.first_service_hour)}<br>
          Last service: ${formatHour(d.last_service_hour)}<br>
          Service span: ${formatNumber(d.service_span_hours, 1)} hrs<br>
          Stops: ${formatInteger(d.n_stops)}<br>
          Routes: ${formatInteger(d.n_routes)}<br>
          Stop events: ${formatInteger(d.n_stop_events)}
        `);
      })
      .on("mousemove", function (event) {
        moveTooltip(event);
      })
      .on("mouseleave", function () {
        hideTooltip();
      });
  });
}


// ============================================================
// DUMBBELL CHART
// Weekday vs weekend service
// ============================================================

function renderDumbbellChart() {
  const container = d3.select("#dumbbell-chart");

  container.html("");

  const node = container.node();
  const width = node.clientWidth;
  const baseHeight = node.clientHeight;

  if (width === 0 || baseHeight === 0) {
    console.warn("Dumbbell chart container has zero width or height.");
    return;
  }

  const topData = getTopMetrics();

  const selectedRows = state.selectedLgas
    .map(lgaCode => getMetricRowByLgaAndMode(lgaCode, state.mode))
    .filter(Boolean);

  const topCodes = new Set(
    topData.map(d => String(d.lga_code))
  );

  // Add selected LGAs only when they are not already in the Top N list.
  // This gives: Top 5 + selected extras, Top 10 + selected extras, etc.
  const selectedExtraRows = selectedRows
    .filter(d => !topCodes.has(String(d.lga_code)));

  const displayData = [
    ...selectedExtraRows.map(d => ({
      ...d,
      is_selected_extra: true
    })),
    ...topData.map(d => ({
      ...d,
      is_selected_extra: false
    }))
  ];

  if (displayData.length === 0) {
    container.html(`
      <div class="placeholder-note">
        No weekday-weekend data available for this selection.
      </div>
    `);
    return;
  }

  const metricLabel = metricLabels[state.metric] || state.metric;

  const chartData = displayData.map(d => {
    return {
      ...d,
      weekday_value: Math.log1p(Math.max(0, d.weekday_stop_events || 0)),
      weekend_value: Math.log1p(Math.max(0, d.weekend_stop_events || 0)),
      weekday_raw: Math.max(0, d.weekday_stop_events || 0),
      weekend_raw: Math.max(0, d.weekend_stop_events || 0)
    };
  });

  const margin = {
    top: 80,
    right: 40,
    bottom: 58,
    left: 154
  };

  // Make the chart taller when Top 20 + selected LGAs creates many rows.
  const rowHeight = 28;
  const dynamicInnerHeight = Math.max(
    230,
    chartData.length * rowHeight
  );

  const height = Math.max(
    baseHeight,
    margin.top + margin.bottom + dynamicInnerHeight
  );

  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;

  const xMax = d3.max(
    chartData,
    d => Math.max(d.weekday_value, d.weekend_value)
  ) || 1;

  const xScale = d3.scaleLinear()
    .domain([0, xMax])
    .nice()
    .range([0, innerWidth]);

  const yScale = d3.scaleBand()
    .domain(chartData.map(d => d.lga_name))
    .range([0, innerHeight])
    .padding(0.32);

  const svg = container
    .append("svg")
    .attr("class", "dumbbell-svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("role", "img")
    .attr(
      "aria-label",
      "Dumbbell chart comparing weekday and weekend service levels"
    );

  svg.append("text")
    .attr("class", "dumbbell-note")
    .attr("x", width - 18)
    .attr("y", 22)
    .attr("text-anchor", "end")
    .text(() => {
      if (state.selectedLgas.length > 0) {
        return `Selected LGAs + Top ${state.topN} by ${metricLabel}`;
      }

      return `Top ${state.topN} by ${metricLabel}`;
    });

  const chart = svg
    .append("g")
    .attr("transform", `translate(${margin.left}, ${margin.top})`);

  const xGrid = d3.axisBottom(xScale)
    .ticks(5)
    .tickSize(-innerHeight)
    .tickFormat("");

  chart.append("g")
    .attr("class", "dumbbell-grid")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xGrid);

  // Connecting lines
  chart.append("g")
    .attr("class", "dumbbell-lines")
    .selectAll("line")
    .data(chartData, d => d.lga_code)
    .join("line")
    .attr("class", "dumbbell-line")
    .attr("x1", d => xScale(d.weekday_value))
    .attr("x2", d => xScale(d.weekend_value))
    .attr("y1", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("y2", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .style("stroke", d => {
      if (isSelectedLga(d.lga_code)) {
        return getSelectionColor(d.lga_code) || "#171717";
      }

      return "rgba(23, 23, 23, 0.22)";
    })
    .attr("stroke-width", d => {
      return isSelectedLga(d.lga_code) ? 3 : 1.6;
    })
    .attr("opacity", d => {
      if (state.selectedLgas.length === 0) {
        return 1;
      }

      return isSelectedLga(d.lga_code) ? 1 : 0.35;
    });

  // Weekday dots
  chart.append("g")
    .attr("class", "weekday-dots")
    .selectAll("circle")
    .data(chartData, d => d.lga_code)
    .join("circle")
    .attr("class", "weekday-dot")
    .attr("cx", d => xScale(d.weekday_value))
    .attr("cy", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("r", d => isSelectedLga(d.lga_code) ? 7 : 5)
    .style("fill", d => {
      if (isSelectedLga(d.lga_code)) {
        return getSelectionColor(d.lga_code) || "#171717";
      }

      return "#2bb8a9";
    })
    .style("stroke", d => {
      return isSelectedLga(d.lga_code)
        ? "#171717"
        : "rgba(23, 23, 23, 0.35)";
    })
    .style("stroke-width", d => {
      return isSelectedLga(d.lga_code) ? 1.8 : 1;
    })
    .attr("opacity", d => {
      if (state.selectedLgas.length === 0) {
        return 1;
      }

      return isSelectedLga(d.lga_code) ? 1 : 0.35;
    });

  // Weekend dots
  chart.append("g")
    .attr("class", "weekend-dots")
    .selectAll("circle")
    .data(chartData, d => d.lga_code)
    .join("circle")
    .attr("class", "weekend-dot")
    .attr("cx", d => xScale(d.weekend_value))
    .attr("cy", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("r", d => isSelectedLga(d.lga_code) ? 7 : 5)
    .style("fill", d => {
      if (isSelectedLga(d.lga_code)) {
        return getSelectionColor(d.lga_code) || "#171717";
      }

      return "#f2a51a";
    })
    .style("stroke", d => {
      return isSelectedLga(d.lga_code)
        ? "#171717"
        : "rgba(23, 23, 23, 0.35)";
    })
    .style("stroke-width", d => {
      return isSelectedLga(d.lga_code) ? 1.8 : 1;
    })
    .attr("opacity", d => {
      if (state.selectedLgas.length === 0) {
        return 1;
      }

      return isSelectedLga(d.lga_code) ? 1 : 0.35;
    });

  // Y labels
  chart.append("g")
    .attr("class", "dumbbell-y-labels")
    .selectAll("text")
    .data(chartData, d => d.lga_code)
    .join("text")
    .attr("x", -12)
    .attr("y", d => yScale(d.lga_name) + yScale.bandwidth() / 2)
    .attr("dy", "0.35em")
    .attr("text-anchor", "end")
    .style("fill", d => {
      if (isSelectedLga(d.lga_code)) {
        return getSelectionColor(d.lga_code) || "#171717";
      }

      return "#171717";
    })
    .style("font-weight", d => {
      return isSelectedLga(d.lga_code) ? 900 : 700;
    })
    .text(d => {
      const prefix = d.is_selected_extra ? "★ " : "";
      return prefix + truncateText(d.lga_name, 20);
    });

  // Hover and click layer
  chart.append("g")
    .attr("class", "dumbbell-hover-layer")
    .selectAll("rect")
    .data(chartData, d => d.lga_code)
    .join("rect")
    .attr("class", "dumbbell-hover-row")
    .attr("x", 0)
    .attr("y", d => yScale(d.lga_name) - 5)
    .attr("width", innerWidth)
    .attr("height", yScale.bandwidth() + 10)
    .on("mouseenter", function (event, d) {
      showTooltip(event, `
        <strong>${d.lga_name}</strong><br>
        Region: ${getMetricRegionType(d)}<br>
        Mode: ${state.mode}<br>
        ${metricLabel}: ${formatNumber(d[state.metric], 1)}<br>
        Weekday stop events: ${formatInteger(d.weekday_raw)}<br>
        Weekend stop events: ${formatInteger(d.weekend_raw)}<br>
        Weekend-weekday gap: ${formatNumber(d.weekend_weekday_gap, 1)}
      `);
    })
    .on("mousemove", function (event) {
      moveTooltip(event);
    })
    .on("mouseleave", function () {
      hideTooltip();
    })
    .on("click", function (event, d) {
      toggleSelectedLga(d.lga_code);

      if (typeof updateMapSelectionStyles === "function") {
        updateMapSelectionStyles();
      }

      updateAll({ skipMap: true });
    });

  const xAxis = d3.axisBottom(xScale)
    .ticks(5)
    .tickSizeOuter(0)
    .tickFormat(d => {
      const originalValue = Math.expm1(d);
      return d3.format("~s")(originalValue);
    });

  chart.append("g")
    .attr("class", "dumbbell-axis")
    .attr("transform", `translate(0, ${innerHeight})`)
    .call(xAxis);

  chart.append("text")
    .attr("class", "dumbbell-axis-label")
    .attr("x", innerWidth)
    .attr("y", innerHeight + 42)
    .attr("text-anchor", "end")
    .text("GTFS stop events, log scale");

  const legend = svg
    .append("g")
    .attr("class", "dumbbell-legend")
    .attr("transform", `translate(${margin.left}, 44)`);

  legend.append("circle")
    .attr("class", "weekday-dot")
    .attr("cx", 0)
    .attr("cy", 0)
    .attr("r", 5)
    .style("fill", "#2bb8a9");

  legend.append("text")
    .attr("x", 10)
    .attr("y", 4)
    .text("Weekday");

  legend.append("circle")
    .attr("class", "weekend-dot")
    .attr("cx", 88)
    .attr("cy", 0)
    .attr("r", 5)
    .style("fill", "#f2a51a");

  legend.append("text")
    .attr("x", 98)
    .attr("y", 4)
    .text("Weekend");

  if (state.selectedLgas.length > 0) {
    legend.append("text")
      .attr("x", 178)
      .attr("y", 4)
      .attr("class", "dumbbell-selected-note")
      .text("★ selected extra");
  }
}

// ============================================================
// CONCLUSION MATRIX
// ============================================================

function renderConclusionMatrix() {
  const container = d3.select("#conclusion-matrix");

  container.html("");

  const modes = ["All", "Bus", "Train", "Tram"];

  const gapFields = [
    {
      key: "coverage_gap",
      label: "Coverage"
    },
    {
      key: "frequency_gap",
      label: "Frequency"
    },
    {
      key: "service_gap",
      label: "Service span"
    },
    {
      key: "weekend_weekday_gap",
      label: "Weekend"
    },
    {
      key: "mode_diversity_gap",
      label: "Mode diversity"
    }
  ];

  const summaryRows = modes.map(mode => {
    const rows = metricsData.filter(d => {
        return d.mode === mode && regionMatches(d);
    });

    const totalLgas = rows.length;
    const servedLgas = rows.filter(d => d.has_service).length;
    const serviceCoverage = totalLgas > 0
      ? servedLgas / totalLgas * 100
      : 0;

    const medianOverall = d3.median(rows, d => d.overall_score);

    const medianGaps = gapFields.map(gap => {
      return {
        key: gap.key,
        label: gap.label,
        value: d3.median(rows, d => d[gap.key])
      };
    });

    const mainGap = medianGaps
      .filter(d => Number.isFinite(d.value))
      .sort((a, b) => d3.descending(a.value, b.value))[0];

    const topUnderserved = rows
      .filter(d => Number.isFinite(d.overall_score))
      .sort((a, b) => {
        return d3.descending(a.overall_score, b.overall_score) ||
          d3.ascending(a.lga_name, b.lga_name);
      })[0];

    return {
      mode,
      totalLgas,
      servedLgas,
      serviceCoverage,
      medianOverall,
      mainGapLabel: mainGap ? mainGap.label : "No data",
      mainGapValue: mainGap ? mainGap.value : null,
      topLgaName: topUnderserved ? topUnderserved.lga_name : "No data",
      topLgaCode: topUnderserved ? topUnderserved.lga_code : null,
      topLgaScore: topUnderserved ? topUnderserved.overall_score : null
    };
  });

  const wrapper = container
    .append("div")
    .attr("class", "conclusion-matrix-wrapper");

  wrapper
    .append("div")
    .attr("class", "conclusion-summary-text")
    .html(`
      <p>
        This matrix summarises the GTFS-based service provision pattern by transport mode.
        Higher scores indicate larger service gaps. Click a row to use that mode as the
        active lens across the linked views.
      </p>
    `);

  const table = wrapper
    .append("table")
    .attr("class", "conclusion-table");

  const thead = table.append("thead");

  thead.append("tr")
    .selectAll("th")
    .data([
      "Mode",
      "LGAs with service",
      "Median gap score",
      "Main gap",
      "Most underserved LGA"
    ])
    .join("th")
    .text(d => d);

  const tbody = table.append("tbody");

  const rows = tbody
    .selectAll("tr")
    .data(summaryRows, d => d.mode)
    .join("tr")
    .attr("class", d => {
      return d.mode === state.mode
        ? "conclusion-row conclusion-row-active"
        : "conclusion-row";
    })
    .on("mouseenter", function (event, d) {
      showTooltip(event, `
        <strong>${d.mode}</strong><br>
        LGAs with service: ${d.servedLgas} / ${d.totalLgas}<br>
        Service availability: ${formatNumber(d.serviceCoverage, 1)}%<br>
        Median overall score: ${formatNumber(d.medianOverall, 1)}<br>
        Main gap: ${d.mainGapLabel} (${formatNumber(d.mainGapValue, 1)})
      `);
    })
    .on("mousemove", function (event) {
      moveTooltip(event);
    })
    .on("mouseleave", function () {
      hideTooltip();
    })
    .on("click", function (event, d) {
      state.mode = d.mode;
      state.selectedLga = null;

      d3.select("#mode-select").property("value", state.mode);

      updateAll();
    });

  rows.append("td")
    .attr("class", "conclusion-mode-cell")
    .html(d => `
      <span class="mode-pill">${d.mode}</span>
    `);

  rows.append("td")
    .html(d => `
      <div class="matrix-main-value">${d.servedLgas} / ${d.totalLgas}</div>
      <div class="matrix-bar-track">
        <div class="matrix-bar-fill" style="width: ${d.serviceCoverage}%"></div>
      </div>
      <div class="matrix-small-note">${formatNumber(d.serviceCoverage, 1)}% of LGAs</div>
    `);

  rows.append("td")
    .html(d => `
      <div class="matrix-score">${formatNumber(d.medianOverall, 1)}</div>
      <div class="matrix-small-note">median</div>
    `);

  rows.append("td")
    .html(d => `
      <div class="matrix-main-value">${d.mainGapLabel}</div>
      <div class="matrix-small-note">${formatNumber(d.mainGapValue, 1)} median gap</div>
    `);

  rows.append("td")
    .html(d => `
      <div class="matrix-main-value">${d.topLgaName}</div>
      <div class="matrix-small-note">${formatNumber(d.topLgaScore, 1)} score</div>
    `);

  wrapper
    .append("p")
    .attr("class", "conclusion-footnote")
    .html(`
      Scores are service-supply inequality proxies derived from GTFS stops, routes,
      stop events, service span, weekend availability, and mode diversity. They are not
      population-adjusted accessibility measures.
    `);
}