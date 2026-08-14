library(readr)
library(janitor)
library(ggplot2)
library(gt)
library(sf)
library(leaflet)
library(dplyr)
library(tidyr)
library(gt)
library(patchwork)

# Data Processing 

# Unzip the GTFS file
dir.create("gtfs_outer", showWarnings = FALSE)
unzip("gtfs.zip", exdir = "gtfs_outer")
# Check the files inside
list.files("gtfs_outer", recursive = TRUE)
# Rename the folders
file.rename('gtfs_outer/1','gtfs_outer/regional_train')
file.rename("gtfs_outer/2", "gtfs_outer/metropolitan_train")
file.rename("gtfs_outer/3", "gtfs_outer/metropolitan_tram")
file.rename("gtfs_outer/4", "gtfs_outer/myki_bus")
file.rename("gtfs_outer/5", "gtfs_outer/regional_coach")
file.rename("gtfs_outer/6", "gtfs_outer/regional_bus")
file.rename("gtfs_outer/10","gtfs_outer/interstate_train")
file.rename("gtfs_outer/11","gtfs_outer/skybus")
# Check the renamed folders
list.files("gtfs_outer")
# Get all transport folders
feed_folders <- list.files("gtfs_outer", full.names = TRUE)
# Unzip the inner google_transit.zip in each folder
for (folder in feed_folders) {
  
  inner_zip <- file.path(folder, "google_transit.zip")
  
  if (file.exists(inner_zip)) {
    unzip(inner_zip, exdir = folder)
  }
}
# Check the extracted files
lapply(list.files("gtfs_outer", full.names = TRUE), list.files)

#Create a folder and unzip for LGA data
dir.create("lga_data", showWarnings = FALSE)
unzip("LGA_2025_AUST_GDA2020.zip", exdir = "lga_data")
list.files("lga_data")

# Read the monthly patronage csv file
monthly_raw <- read_csv(
  "monthly_average_patronage_by_day_type_and_by_mode.csv")
# Column names changed to lowercase
monthly_raw <- clean_names(monthly_raw)
names(monthly_raw)
head(monthly_raw)

#Data Wrangling

# Define the 6 core tables and key fields
target_fields <- list(
  stops = c("stop_id", "stop_name", "stop_lat", "stop_lon"),
  stop_times = c("trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"),
  trips = c("trip_id", "route_id", "service_id"),
  routes = c("route_id", "route_type"),
  calendar = c("service_id", "monday", "tuesday", "wednesday", "thursday",
               "friday", "saturday", "sunday", "start_date", "end_date"),
  calendar_dates = c("service_id", "date", "exception_type")
)

# Read the .txt files from each transport type folder into R and save them as gtfs_feeds.
gtfs_feeds <- list()
  # Read txt files in each folder
for (folder in feed_folders) {
  
  feed_name <- basename(folder)
  txt_files <- list.files(folder, pattern = "\\.txt$", full.names = TRUE)
  
  one_feed <- list()
  
  for (file in txt_files) {
    
    table_name <- tools::file_path_sans_ext(basename(file))
    
    one_feed[[table_name]] <- read.csv(
      file,
      stringsAsFactors = FALSE
    )
  }
  
  gtfs_feeds[[feed_name]] <- one_feed
}
names(gtfs_feeds)
lapply(gtfs_feeds, names)
# Check missing values
missing_detail <- do.call(
  rbind,
  lapply(names(gtfs_feeds), function(feed_name) {
    feed <- gtfs_feeds[[feed_name]]
    do.call(
      rbind,
      lapply(names(target_fields), function(table_name) {
        # Skip if the table does not exist
        if (!table_name %in% names(feed)) {
          return(NULL)
        }
        df <- feed[[table_name]]
        fields <- target_fields[[table_name]]
        # Keep only fields that exist in the table
        fields <- fields[fields %in% names(df)]
        do.call(
          rbind,
          lapply(fields, function(field_name) {
            data.frame(
              feed = feed_name,
              table = table_name,
              field = field_name,
              missing_count = sum(is.na(df[[field_name]])),
              stringsAsFactors = FALSE
            )
          })
        )
      })
    )
  })
)
missing_detail
table_summary <- aggregate(
  missing_count ~ feed + table,
  data = missing_detail,
  sum
)
table_summary
ggplot(table_summary, aes(x = table, y = feed, fill = missing_count)) +
  geom_tile(color = "white") +
  geom_text(aes(label = missing_count), size = 3) +
  labs(
    title = "Missing values in key GTFS fields",
    x = "GTFS table",
    y = "GTFS feed",
    fill = "Missing count"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# Check the key is match or not match
match_summary <- do.call(
  rbind,
  lapply(names(gtfs_feeds), function(feed_name) {
    
    feed <- gtfs_feeds[[feed_name]]
    service_ids_all <- unique(c(feed$calendar$service_id, feed$calendar_dates$service_id))
    
    data.frame(
      feed = feed_name,
      stop_times_trip_to_trips = sum(!feed$stop_times$trip_id %in% feed$trips$trip_id),
      stop_times_stop_to_stops = sum(!feed$stop_times$stop_id %in% feed$stops$stop_id),
      trips_route_to_routes = sum(!feed$trips$route_id %in% feed$routes$route_id),
      trips_service_to_calendar = sum(!feed$trips$service_id %in% service_ids_all),
      stringsAsFactors = FALSE
    )
  })
)

match_summary
# Visualization 
# Copy match_summary
match_table <- match_summary
# Rename the columns
names(match_table) <- c(
  "GTFS feed",
  "Unmatched trip_id in stop_times & trips",
  "Unmatched stop_id in stop_times & stops",
  "Unmatched route_id in trips & routes",
  "Unmatched service_id in trips & calendar"
)
# Sort the rows
match_table <- match_table[order(match_table$`GTFS feed`), ]
# Create a formatted table
gt_table <- gt(match_table) |>
  tab_header(
    title = "GTFS key matching check"
  )
gt_table

# filter LGA data to VIC
lga_raw <- st_read("lga_data/LGA_2025_AUST_GDA2020.shp", quiet = TRUE)
lga_vic <- lga_raw[lga_raw$STE_NAME21 == "Victoria", ]
# transform CRS for leaflet
lga_vic_map <- st_transform(lga_vic, 4326)
leaflet() %>%
  addTiles() %>%
  addPolygons(
    data = lga_vic_map,
    weight = 1,
    color = "black",
    fillColor = "lightblue",
    fillOpacity = 0.5
  )

# Count NA values in each column
na_summary_monthly <- data.frame(
  column = names(monthly_raw),
  na_count = sapply(monthly_raw, function(x) sum(is.na(x)))
)

na_summary_monthly
barplot(
  na_summary_monthly$na_count,
  names.arg = na_summary_monthly$column,
  las = 2,
  main = "NA values in monthly patronage data",
  ylab = "Number of NA values"
)




# Question 1
# Keep only selected feeds for Figure 1
selected_feeds <- c(
  "interstate_train",
  "metropolitan_train",
  "regional_train",
  "myki_bus",
  "regional_bus",
  "metropolitan_tram"
)

gtfs_q1 <- gtfs_feeds[selected_feeds]

# Create a simple feed-to-mode map
feed_group <- data.frame(
  feed = c(
    "interstate_train",
    "metropolitan_train",
    "regional_train",
    "myki_bus",
    "regional_bus",
    "metropolitan_tram"
  ),
  mode = c(
    "Train",
    "Train",
    "Train",
    "Bus",
    "Bus",
    "Tram"
  ),
  stringsAsFactors = FALSE
)

# Check the result
names(gtfs_q1)
feed_group
# Extract train stops
train_stops <- bind_rows(
  mutate(gtfs_feeds$interstate_train$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$metropolitan_train$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$regional_train$stops, stop_id = as.character(stop_id))
)

# Extract bus stops
bus_stops <- bind_rows(
  mutate(gtfs_feeds$myki_bus$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$regional_bus$stops, stop_id = as.character(stop_id))
)

# Extract tram stops
tram_stops <- gtfs_feeds$metropolitan_tram$stops %>%
  mutate(stop_id = as.character(stop_id))

# Remove duplicate stop records
train_stops <- distinct(train_stops)
bus_stops <- distinct(bus_stops)
tram_stops <- distinct(tram_stops)

# Check the result
nrow(train_stops)
nrow(bus_stops)
nrow(tram_stops)

# Transfer train_stops into LGA spatial data
# Keep only needed columns
train_stops_use <- train_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
train_stops_sf <- st_as_sf(
  train_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
train_stops_lga <- st_join(
  train_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
head(train_stops_lga)

# Transfer bus_stops into LGA
# Keep only needed columns
bus_stops_use <- bus_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
bus_stops_sf <- st_as_sf(
  bus_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
bus_stops_lga <- st_join(
  bus_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
# Check result
head(bus_stops_lga)

# transfer tram_stops into LGA
# Keep only needed columns
tram_stops_use <- tram_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
tram_stops_sf <- st_as_sf(
  tram_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
tram_stops_lga <- st_join(
  tram_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
# Check result
head(tram_stops_lga)

# Check NA value about cord
sum(is.na(train_stops_lga$LGA_CODE25))
sum(is.na(bus_stops_lga$LGA_CODE25))
sum(is.na(tram_stops_lga$LGA_CODE25))

# Count the number of sites for each LGA separately
# Train stop count by LGA
train_lga_count <- train_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Train")

# Bus stop count by LGA
bus_lga_count <- bus_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Bus")

# Tram stop count by LGA
tram_lga_count <- tram_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Tram")

q1_stop_count <- bind_rows(
  train_lga_count,
  bus_lga_count,
  tram_lga_count
)

# Create all LGA x mode combinations
lga_list <- st_drop_geometry(lga_vic_map)[, c("LGA_CODE25", "LGA_NAME25")]
mode_list <- data.frame(
  mode = c("Train", "Bus", "Tram"),
  stringsAsFactors = FALSE
)
lga_mode_all <- merge(lga_list, mode_list, by = NULL)
# Join stop counts to all combinations
q1_stop_count_full <- merge(
  lga_mode_all,
  q1_stop_count,
  by = c("LGA_CODE25", "LGA_NAME25", "mode"),
  all.x = TRUE
)
# Replace NA with 0
q1_stop_count_full$stop_count[is.na(q1_stop_count_full$stop_count)] <- 0
# Set mode order
q1_stop_count_full$mode <- factor(
  q1_stop_count_full$mode,
  levels = c("Train", "Bus", "Tram")
)
# Join back to map
q1_map_data <- merge(
  lga_vic_map,
  q1_stop_count_full,
  by = c("LGA_CODE25", "LGA_NAME25"),
  all.x = TRUE
)
q1_map_data$stop_count_plot <- ifelse(q1_map_data$stop_count == 0, NA, q1_map_data$stop_count)
# Create a map
p1 <- ggplot() +
  # Layer 1: show zero-count LGAs in light grey
  geom_sf(
    data = q1_map_data[q1_map_data$stop_count == 0, ],
    fill = "lightgrey",
    color = "grey",
    size = 0.1
  ) +
  # Layer 2: show positive-count LGAs with gradient
  geom_sf(
    data = q1_map_data[q1_map_data$stop_count > 0, ],
    aes(fill = stop_count_plot),
    color = "grey",
    size = 0.1
  ) +
  facet_wrap(~ mode, nrow = 1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Public transport stop coverage across Victoria",
    subtitle = "Grey indicates zero stops",
    fill = "Stop count"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

p1



# Extract train stop_times
train_stop_times <- bind_rows(
  mutate(
    gtfs_feeds$interstate_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "interstate_train",
    mode = "Train"
  ),
  mutate(
    gtfs_feeds$metropolitan_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "metropolitan_train",
    mode = "Train"
  ),
  mutate(
    gtfs_feeds$regional_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "regional_train",
    mode = "Train"
  )
)
# Extract bus stop_times
bus_stop_times <- bind_rows(
  mutate(
    gtfs_feeds$myki_bus$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "myki_bus",
    mode = "Bus"
  ),
  mutate(
    gtfs_feeds$regional_bus$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "regional_bus",
    mode = "Bus"
  )
)

# Extract tram stop_times
tram_stop_times <- gtfs_feeds$metropolitan_tram$stop_times[, c("trip_id", "stop_id", "departure_time")] %>%
  mutate(
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "metropolitan_tram",
    mode = "Tram"
  )
# Check the result
head(train_stop_times)
head(bus_stop_times)
head(tram_stop_times)

# Separate the departure time into 3 time zones: Morning rush hour, evening rush hour and lunch break
# Step 1: Create a function to classify departure_time
get_time_band <- function(time_value) {
  hour <- as.numeric(sub(":.*", "", as.character(time_value)))
  hour <- hour %% 24
  # Classify into 3 time bands
  ifelse(hour >= 7 & hour < 10, "Morning peak",
         ifelse(hour >= 10 & hour < 15, "Midday",
                ifelse(hour >= 15 & hour < 20, "Evening peak", "Other")))
}
# Apply to train stop_times without other
train_stop_times <- train_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")
# Apply to bus stop_times without other
bus_stop_times <- bus_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")
# Apply to tram stop_times without other
tram_stop_times <- tram_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")

# Extract trips (stop_times first connects to trips via trip_id)
# train trips
train_trips <- bind_rows(
  mutate(gtfs_feeds$interstate_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "interstate_train"),
  mutate(gtfs_feeds$metropolitan_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "metropolitan_train"),
  mutate(gtfs_feeds$regional_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "regional_train")
)
# Bus trips
bus_trips <- bind_rows(
  mutate(gtfs_feeds$myki_bus$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "myki_bus"),
  mutate(gtfs_feeds$regional_bus$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "regional_bus")
)
# tram trips
tram_trips <- gtfs_feeds$metropolitan_tram$trips[, c("trip_id", "service_id")] %>%
  mutate(
    trip_id = as.character(trip_id),
    service_id = as.character(service_id),
    feed = "metropolitan_tram"
  )

# extract Calendar
# train calendar
train_calendar <- bind_rows(
  mutate(gtfs_feeds$interstate_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "interstate_train"),
  mutate(gtfs_feeds$metropolitan_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "metropolitan_train"),
  mutate(gtfs_feeds$regional_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "regional_train")
)
# bus calendar
bus_calendar <- bind_rows(
  mutate(gtfs_feeds$myki_bus$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "myki_bus"),
  mutate(gtfs_feeds$regional_bus$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "regional_bus")
)
# Tram calendar
tram_calendar <- gtfs_feeds$metropolitan_tram$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")] %>%
  mutate(
    service_id = as.character(service_id),
    feed = "metropolitan_tram"
  )

# Generate train day type (weekend/weekday)
# train day type
train_day_type <- bind_rows(
  train_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  train_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)
# bus day type
bus_day_type <- bind_rows(
  bus_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  bus_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)
# tram day type
tram_day_type <- bind_rows(
  tram_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  tram_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)

# Finally, link back to stop_times
# train time data
train_time_data <- train_stop_times %>%
  left_join(train_trips, by = c("feed", "trip_id")) %>%
  left_join(train_day_type, by = c("feed", "service_id"))
# bus time data
bus_time_data <- bus_stop_times %>%
  left_join(bus_trips, by = c("feed", "trip_id")) %>%
  left_join(bus_day_type, by = c("feed", "service_id"))
# tram time data
tram_time_data <- tram_stop_times %>%
  left_join(tram_trips, by = c("feed", "trip_id")) %>%
  left_join(tram_day_type, by = c("feed", "service_id"))

# Combine the three tables
time_data_all <- bind_rows(
  train_time_data,
  bus_time_data,
  tram_time_data
)
# Count departures by mode, time band, and day type
time_summary <- time_data_all %>%
  filter(!is.na(day_type)) %>%
  group_by(mode, time_band, day_type) %>%
  summarise(
    departures_n = n_distinct(paste(feed, trip_id)),
    .groups = "drop"
  )
# Set the order for plotting
time_summary$mode <- factor(
  time_summary$mode,
  levels = c("Train", "Bus", "Tram")
)
time_summary$time_band <- factor(
  time_summary$time_band,
  levels = c("Morning peak", "Midday", "Evening peak")
)
time_summary$day_type <- factor(
  time_summary$day_type,
  levels = c("Weekday", "Weekend")
)
time_summary

# create a heat map
ggplot(time_summary, aes(x = time_band, y = mode, fill = departures_n)) +
  geom_tile(color = "white") +
  geom_text(aes(label = departures_n), size = 4) +
  facet_wrap(~ day_type) +
  scale_fill_gradient(low = "lightblue", high = "darkblue") +
  labs(
    title = "Public transport service intensity by time band",
    subtitle = "Number of unique trips by mode and day type",
    x = "Time band",
    y = "Transport mode",
    fill = "Trips"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold"),
    axis.text.x = element_text(angle = 15, hjust = 1)
  )

q1_small_table <- time_summary %>%
  group_by(mode, day_type) %>%
  summarise(
    total_trips = sum(departures_n),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = day_type,
    values_from = total_trips,
    values_fill = 0
  ) %>%
  mutate(
    Total = Weekday + Weekend,
    `Weekend / Weekday ratio` = round(Weekend / Weekday, 2)
  ) %>%
  select(mode, Weekday, Weekend, Total, `Weekend / Weekday ratio`)

# Show as a formatted table
gt(q1_small_table) %>%
  tab_header(
    title = "Summary of service intensity by transport mode"
  ) %>%
  cols_label(
    mode = "Transport mode",
    Weekday = "Weekday trips",
    Weekend = "Weekend trips",
    Total = "Total trips",
    `Weekend / Weekday ratio` = "Weekend / Weekday"
  ) 




# Question 2
# stop density
# Combine all stop tables
library(readr)
library(janitor)
library(ggplot2)
library(gt)
library(sf)
library(leaflet)
library(dplyr)
library(tidyr)
library(gt)

# Data Processing 

# Unzip the GTFS file
dir.create("gtfs_outer", showWarnings = FALSE)
unzip("gtfs.zip", exdir = "gtfs_outer")
# Check the files inside
list.files("gtfs_outer", recursive = TRUE)
# Rename the folders
file.rename('gtfs_outer/1','gtfs_outer/regional_train')
file.rename("gtfs_outer/2", "gtfs_outer/metropolitan_train")
file.rename("gtfs_outer/3", "gtfs_outer/metropolitan_tram")
file.rename("gtfs_outer/4", "gtfs_outer/myki_bus")
file.rename("gtfs_outer/5", "gtfs_outer/regional_coach")
file.rename("gtfs_outer/6", "gtfs_outer/regional_bus")
file.rename("gtfs_outer/10","gtfs_outer/interstate_train")
file.rename("gtfs_outer/11","gtfs_outer/skybus")
# Check the renamed folders
list.files("gtfs_outer")
# Get all transport folders
feed_folders <- list.files("gtfs_outer", full.names = TRUE)
# Unzip the inner google_transit.zip in each folder
for (folder in feed_folders) {
  
  inner_zip <- file.path(folder, "google_transit.zip")
  
  if (file.exists(inner_zip)) {
    unzip(inner_zip, exdir = folder)
  }
}
# Check the extracted files
lapply(list.files("gtfs_outer", full.names = TRUE), list.files)

#Create a folder and unzip for LGA data
dir.create("lga_data", showWarnings = FALSE)
unzip("LGA_2025_AUST_GDA2020.zip", exdir = "lga_data")
list.files("lga_data")

# Read the monthly patronage csv file
monthly_raw <- read_csv(
  "monthly_average_patronage_by_day_type_and_by_mode.csv")
# Column names changed to lowercase
monthly_raw <- clean_names(monthly_raw)
names(monthly_raw)
head(monthly_raw)

#Data Wrangling

# Define the 6 core tables and key fields
target_fields <- list(
  stops = c("stop_id", "stop_name", "stop_lat", "stop_lon"),
  stop_times = c("trip_id", "arrival_time", "departure_time", "stop_id", "stop_sequence"),
  trips = c("trip_id", "route_id", "service_id"),
  routes = c("route_id", "route_type"),
  calendar = c("service_id", "monday", "tuesday", "wednesday", "thursday",
               "friday", "saturday", "sunday", "start_date", "end_date"),
  calendar_dates = c("service_id", "date", "exception_type")
)

# Read the .txt files from each transport type folder into R and save them as gtfs_feeds.
gtfs_feeds <- list()
# Read txt files in each folder
for (folder in feed_folders) {
  
  feed_name <- basename(folder)
  txt_files <- list.files(folder, pattern = "\\.txt$", full.names = TRUE)
  
  one_feed <- list()
  
  for (file in txt_files) {
    
    table_name <- tools::file_path_sans_ext(basename(file))
    
    one_feed[[table_name]] <- read.csv(
      file,
      stringsAsFactors = FALSE
    )
  }
  
  gtfs_feeds[[feed_name]] <- one_feed
}
names(gtfs_feeds)
lapply(gtfs_feeds, names)
# Check missing values
missing_detail <- do.call(
  rbind,
  lapply(names(gtfs_feeds), function(feed_name) {
    feed <- gtfs_feeds[[feed_name]]
    do.call(
      rbind,
      lapply(names(target_fields), function(table_name) {
        # Skip if the table does not exist
        if (!table_name %in% names(feed)) {
          return(NULL)
        }
        df <- feed[[table_name]]
        fields <- target_fields[[table_name]]
        # Keep only fields that exist in the table
        fields <- fields[fields %in% names(df)]
        do.call(
          rbind,
          lapply(fields, function(field_name) {
            data.frame(
              feed = feed_name,
              table = table_name,
              field = field_name,
              missing_count = sum(is.na(df[[field_name]])),
              stringsAsFactors = FALSE
            )
          })
        )
      })
    )
  })
)
missing_detail
table_summary <- aggregate(
  missing_count ~ feed + table,
  data = missing_detail,
  sum
)
table_summary
ggplot(table_summary, aes(x = table, y = feed, fill = missing_count)) +
  geom_tile(color = "white") +
  geom_text(aes(label = missing_count), size = 3) +
  labs(
    title = "Missing values in key GTFS fields",
    x = "GTFS table",
    y = "GTFS feed",
    fill = "Missing count"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# Check the key is match or not match
match_summary <- do.call(
  rbind,
  lapply(names(gtfs_feeds), function(feed_name) {
    
    feed <- gtfs_feeds[[feed_name]]
    service_ids_all <- unique(c(feed$calendar$service_id, feed$calendar_dates$service_id))
    
    data.frame(
      feed = feed_name,
      stop_times_trip_to_trips = sum(!feed$stop_times$trip_id %in% feed$trips$trip_id),
      stop_times_stop_to_stops = sum(!feed$stop_times$stop_id %in% feed$stops$stop_id),
      trips_route_to_routes = sum(!feed$trips$route_id %in% feed$routes$route_id),
      trips_service_to_calendar = sum(!feed$trips$service_id %in% service_ids_all),
      stringsAsFactors = FALSE
    )
  })
)

match_summary
# Visualization 
# Copy match_summary
match_table <- match_summary
# Rename the columns
names(match_table) <- c(
  "GTFS feed",
  "Unmatched trip_id in stop_times & trips",
  "Unmatched stop_id in stop_times & stops",
  "Unmatched route_id in trips & routes",
  "Unmatched service_id in trips & calendar"
)
# Sort the rows
match_table <- match_table[order(match_table$`GTFS feed`), ]
# Create a formatted table
gt_table <- gt(match_table) |>
  tab_header(
    title = "GTFS key matching check"
  )
gt_table

# filter LGA data to VIC
lga_raw <- st_read("lga_data/LGA_2025_AUST_GDA2020.shp", quiet = TRUE)
lga_vic <- lga_raw[lga_raw$STE_NAME21 == "Victoria", ]
# transform CRS for leaflet
lga_vic_map <- st_transform(lga_vic, 4326)
leaflet() %>%
  addTiles() %>%
  addPolygons(
    data = lga_vic_map,
    weight = 1,
    color = "black",
    fillColor = "lightblue",
    fillOpacity = 0.5
  )

# Count NA values in each column
na_summary_monthly <- data.frame(
  column = names(monthly_raw),
  na_count = sapply(monthly_raw, function(x) sum(is.na(x)))
)

na_summary_monthly
barplot(
  na_summary_monthly$na_count,
  names.arg = na_summary_monthly$column,
  las = 2,
  main = "NA values in monthly patronage data",
  ylab = "Number of NA values"
)




# Question 1
# Keep only selected feeds for Figure 1
selected_feeds <- c(
  "interstate_train",
  "metropolitan_train",
  "regional_train",
  "myki_bus",
  "regional_bus",
  "metropolitan_tram"
)

gtfs_q1 <- gtfs_feeds[selected_feeds]

# Create a simple feed-to-mode map
feed_group <- data.frame(
  feed = c(
    "interstate_train",
    "metropolitan_train",
    "regional_train",
    "myki_bus",
    "regional_bus",
    "metropolitan_tram"
  ),
  mode = c(
    "Train",
    "Train",
    "Train",
    "Bus",
    "Bus",
    "Tram"
  ),
  stringsAsFactors = FALSE
)

# Check the result
names(gtfs_q1)
feed_group
# Extract train stops
train_stops <- bind_rows(
  mutate(gtfs_feeds$interstate_train$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$metropolitan_train$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$regional_train$stops, stop_id = as.character(stop_id))
)

# Extract bus stops
bus_stops <- bind_rows(
  mutate(gtfs_feeds$myki_bus$stops, stop_id = as.character(stop_id)),
  mutate(gtfs_feeds$regional_bus$stops, stop_id = as.character(stop_id))
)

# Extract tram stops
tram_stops <- gtfs_feeds$metropolitan_tram$stops %>%
  mutate(stop_id = as.character(stop_id))

# Remove duplicate stop records
train_stops <- distinct(train_stops)
bus_stops <- distinct(bus_stops)
tram_stops <- distinct(tram_stops)

# Check the result
nrow(train_stops)
nrow(bus_stops)
nrow(tram_stops)

# Transfer train_stops into LGA spatial data
# Keep only needed columns
train_stops_use <- train_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
train_stops_sf <- st_as_sf(
  train_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
train_stops_lga <- st_join(
  train_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
head(train_stops_lga)

# Transfer bus_stops into LGA
# Keep only needed columns
bus_stops_use <- bus_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
bus_stops_sf <- st_as_sf(
  bus_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
bus_stops_lga <- st_join(
  bus_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
# Check result
head(bus_stops_lga)

# transfer tram_stops into LGA
# Keep only needed columns
tram_stops_use <- tram_stops %>%
  select(stop_id, stop_lat, stop_lon) %>%
  distinct()
# Turn into sf points
tram_stops_sf <- st_as_sf(
  tram_stops_use,
  coords = c("stop_lon", "stop_lat"),
  crs = 4326,
  remove = FALSE
)
# Match to LGA
tram_stops_lga <- st_join(
  tram_stops_sf,
  lga_vic_map %>% select(LGA_CODE25, LGA_NAME25),
  join = st_within,
  left = TRUE
) %>%
  st_drop_geometry()
# Check result
head(tram_stops_lga)

# Check NA value about cord
sum(is.na(train_stops_lga$LGA_CODE25))
sum(is.na(bus_stops_lga$LGA_CODE25))
sum(is.na(tram_stops_lga$LGA_CODE25))

# Count the number of sites for each LGA separately
# Train stop count by LGA
train_lga_count <- train_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Train")

# Bus stop count by LGA
bus_lga_count <- bus_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Bus")

# Tram stop count by LGA
tram_lga_count <- tram_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(stop_count = n_distinct(stop_id), .groups = "drop") %>%
  mutate(mode = "Tram")

q1_stop_count <- bind_rows(
  train_lga_count,
  bus_lga_count,
  tram_lga_count
)

# Create all LGA x mode combinations
lga_list <- st_drop_geometry(lga_vic_map)[, c("LGA_CODE25", "LGA_NAME25")]
mode_list <- data.frame(
  mode = c("Train", "Bus", "Tram"),
  stringsAsFactors = FALSE
)
lga_mode_all <- merge(lga_list, mode_list, by = NULL)
# Join stop counts to all combinations
q1_stop_count_full <- merge(
  lga_mode_all,
  q1_stop_count,
  by = c("LGA_CODE25", "LGA_NAME25", "mode"),
  all.x = TRUE
)
# Replace NA with 0
q1_stop_count_full$stop_count[is.na(q1_stop_count_full$stop_count)] <- 0
# Set mode order
q1_stop_count_full$mode <- factor(
  q1_stop_count_full$mode,
  levels = c("Train", "Bus", "Tram")
)
# Join back to map
q1_map_data <- merge(
  lga_vic_map,
  q1_stop_count_full,
  by = c("LGA_CODE25", "LGA_NAME25"),
  all.x = TRUE
)
q1_map_data$stop_count_plot <- ifelse(q1_map_data$stop_count == 0, NA, q1_map_data$stop_count)
# Create a map
p1 <- ggplot() +
  # Layer 1: show zero-count LGA in light grey
  geom_sf(
    data = q1_map_data[q1_map_data$stop_count == 0, ],
    fill = "lightgrey",
    color = "grey",
    size = 0.1
  ) +
  # Layer 2: show positive-count LGAs with gradient
  geom_sf(
    data = q1_map_data[q1_map_data$stop_count > 0, ],
    aes(fill = stop_count_plot),
    color = "grey",
    size = 0.1
  ) +
  facet_wrap(~ mode, nrow = 1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Public transport stop coverage across Victoria",
    subtitle = "Grey indicates zero stops",
    fill = "Stop count"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

p1



# Extract train stop_times
train_stop_times <- bind_rows(
  mutate(
    gtfs_feeds$interstate_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "interstate_train",
    mode = "Train"
  ),
  mutate(
    gtfs_feeds$metropolitan_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "metropolitan_train",
    mode = "Train"
  ),
  mutate(
    gtfs_feeds$regional_train$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "regional_train",
    mode = "Train"
  )
)
# Extract bus stop_times
bus_stop_times <- bind_rows(
  mutate(
    gtfs_feeds$myki_bus$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "myki_bus",
    mode = "Bus"
  ),
  mutate(
    gtfs_feeds$regional_bus$stop_times[, c("trip_id", "stop_id", "departure_time")],
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "regional_bus",
    mode = "Bus"
  )
)

# Extract tram stop_times
tram_stop_times <- gtfs_feeds$metropolitan_tram$stop_times[, c("trip_id", "stop_id", "departure_time")] %>%
  mutate(
    trip_id = as.character(trip_id),
    stop_id = as.character(stop_id),
    feed = "metropolitan_tram",
    mode = "Tram"
  )
# Check the result
head(train_stop_times)
head(bus_stop_times)
head(tram_stop_times)

# Separate the departure time into 3 time zones: Morning rush hour, evening rush hour and lunch break
# Create a function to classify departure_time
get_time_band <- function(time_value) {
  hour <- as.numeric(sub(":.*", "", as.character(time_value)))
  hour <- hour %% 24
  # Classify into 3 time bands
  ifelse(hour >= 7 & hour < 10, "Morning peak",
         ifelse(hour >= 10 & hour < 15, "Midday",
                ifelse(hour >= 15 & hour < 20, "Evening peak", "Other")))
}
# Apply to train stop_times without other
train_stop_times <- train_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")
# Apply to bus stop_times without other
bus_stop_times <- bus_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")
# Apply to tram stop_times without other
tram_stop_times <- tram_stop_times %>%
  mutate(time_band = get_time_band(departure_time)) %>%
  filter(time_band != "Other")

# Extract trips (stop_times first connects to trips via trip_id)
# train trips
train_trips <- bind_rows(
  mutate(gtfs_feeds$interstate_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "interstate_train"),
  mutate(gtfs_feeds$metropolitan_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "metropolitan_train"),
  mutate(gtfs_feeds$regional_train$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "regional_train")
)
# Bus trips
bus_trips <- bind_rows(
  mutate(gtfs_feeds$myki_bus$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "myki_bus"),
  mutate(gtfs_feeds$regional_bus$trips[, c("trip_id", "service_id")],
         trip_id = as.character(trip_id),
         service_id = as.character(service_id),
         feed = "regional_bus")
)
# tram trips
tram_trips <- gtfs_feeds$metropolitan_tram$trips[, c("trip_id", "service_id")] %>%
  mutate(
    trip_id = as.character(trip_id),
    service_id = as.character(service_id),
    feed = "metropolitan_tram"
  )
# extract Calendar
# train calendar
train_calendar <- bind_rows(
  mutate(gtfs_feeds$interstate_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "interstate_train"),
  mutate(gtfs_feeds$metropolitan_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "metropolitan_train"),
  mutate(gtfs_feeds$regional_train$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "regional_train")
)
# bus calendar
bus_calendar <- bind_rows(
  mutate(gtfs_feeds$myki_bus$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "myki_bus"),
  mutate(gtfs_feeds$regional_bus$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")],
         service_id = as.character(service_id),
         feed = "regional_bus")
)
# Tram calendar
tram_calendar <- gtfs_feeds$metropolitan_tram$calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")] %>%
  mutate(
    service_id = as.character(service_id),
    feed = "metropolitan_tram"
  )

# Generate train day type (weekend/weekday)
# train day type
train_day_type <- bind_rows(
  train_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  train_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)
# bus day type
bus_day_type <- bind_rows(
  bus_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  bus_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)
# tram day type
tram_day_type <- bind_rows(
  tram_calendar %>%
    filter(monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1) %>%
    transmute(feed, service_id, day_type = "Weekday"),
  tram_calendar %>%
    filter(saturday == 1 | sunday == 1) %>%
    transmute(feed, service_id, day_type = "Weekend")
)
# Finally, link back to stop_times
# train time data
train_time_data <- train_stop_times %>%
  left_join(train_trips, by = c("feed", "trip_id")) %>%
  left_join(train_day_type, by = c("feed", "service_id"))
# bus time data
bus_time_data <- bus_stop_times %>%
  left_join(bus_trips, by = c("feed", "trip_id")) %>%
  left_join(bus_day_type, by = c("feed", "service_id"))
# tram time data
tram_time_data <- tram_stop_times %>%
  left_join(tram_trips, by = c("feed", "trip_id")) %>%
  left_join(tram_day_type, by = c("feed", "service_id"))
# Combine the three tables
time_data_all <- bind_rows(
  train_time_data,
  bus_time_data,
  tram_time_data
)
# Count departures by mode, time band, and day type
time_summary <- time_data_all %>%
  filter(!is.na(day_type)) %>%
  group_by(mode, time_band, day_type) %>%
  summarise(
    departures_n = n_distinct(paste(feed, trip_id)),
    .groups = "drop"
  )
# Set the order for plotting
time_summary$mode <- factor(
  time_summary$mode,
  levels = c("Train", "Bus", "Tram")
)
time_summary$time_band <- factor(
  time_summary$time_band,
  levels = c("Morning peak", "Midday", "Evening peak")
)
time_summary$day_type <- factor(
  time_summary$day_type,
  levels = c("Weekday", "Weekend")
)
time_summary
# create a heat map
ggplot(time_summary, aes(x = time_band, y = mode, fill = departures_n)) +
  geom_tile(color = "white") +
  geom_text(aes(label = departures_n), size = 4) +
  facet_wrap(~ day_type) +
  scale_fill_gradient(low = "lightblue", high = "darkblue") +
  labs(
    title = "Public transport service intensity by time band",
    subtitle = "Number of unique trips by mode and day type",
    x = "Time band",
    y = "Transport mode",
    fill = "Trips"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 12, face = "bold"),
    plot.title = element_text(size = 14, face = "bold"),
    axis.text.x = element_text(angle = 15, hjust = 1)
  )

q1_small_table <- time_summary %>%
  group_by(mode, day_type) %>%
  summarise(
    total_trips = sum(departures_n),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = day_type,
    values_from = total_trips,
    values_fill = 0
  ) %>%
  mutate(
    Total = Weekday + Weekend,
    `Weekend / Weekday ratio` = round(Weekend / Weekday, 2)
  ) %>%
  select(mode, Weekday, Weekend, Total, `Weekend / Weekday ratio`)
# Show as a formatted table
gt(q1_small_table) %>%
  tab_header(
    title = "Summary of service intensity by transport mode"
  ) %>%
  cols_label(
    mode = "Transport mode",
    Weekday = "Weekday trips",
    Weekend = "Weekend trips",
    Total = "Total trips",
    `Weekend / Weekday ratio` = "Weekend / Weekday"
  ) 





# Question 2
# stop density
# Add mode to each table
train_stops_lga <- train_stops_lga %>%
  mutate(mode = "Train")
bus_stops_lga <- bus_stops_lga %>%
  mutate(mode = "Bus")
tram_stops_lga <- tram_stops_lga %>%
  mutate(mode = "Tram")
# Combine all stop tables
all_stops_lga <- bind_rows(
  train_stops_lga,
  bus_stops_lga,
  tram_stops_lga
)
# Keep only stops matched to an LGA
all_stops_lga <- all_stops_lga %>%
  filter(!is.na(LGA_CODE25)) %>%
  distinct(mode, stop_id, LGA_CODE25, LGA_NAME25)
# Count stops in each LGA
stop_count_lga <- all_stops_lga %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(
    stop_count = n(),
    .groups = "drop"
  )
# Join stop counts back to the LGA map
stop_density_map <- lga_vic_map %>%
  left_join(stop_count_lga, by = c("LGA_CODE25", "LGA_NAME25"))
# Replace missing stop counts with 0
stop_density_map$stop_count[is.na(stop_density_map$stop_count)] <- 0
# Calculate stop density
stop_density_map <- stop_density_map %>%
  mutate(
    stop_density = stop_count / AREASQKM
  )
# Plot the map
q2_p1 <- ggplot(stop_density_map) +
  geom_sf(aes(fill = stop_density), color = "grey", size = 0.1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Stop density across LGAs in Victoria",
    subtitle = "Number of stops per square kilometre",
    fill = "Stop density"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )




# Question 2
# service frequency
# Combine all stop-LGA tables
all_stops_lga <- bind_rows(
  train_stops_lga,
  bus_stops_lga,
  tram_stops_lga
) %>%
  filter(!is.na(LGA_CODE25)) %>%
  distinct(mode, stop_id, LGA_CODE25, LGA_NAME25)

# Combine all time tables
all_time_data <- bind_rows(
  train_time_data,
  bus_time_data,
  tram_time_data
)

# Match each service record to an LGA
service_lga_data <- all_time_data %>%
  left_join(
    all_stops_lga %>% select(mode, stop_id, LGA_CODE25, LGA_NAME25),
    by = c("mode", "stop_id")
  ) %>%
  filter(!is.na(LGA_CODE25))

# Count service frequency in each LGA
service_frequency_lga <- service_lga_data %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(
    service_frequency = n_distinct(paste(feed, trip_id)),
    .groups = "drop"
  )

# Join back to the LGA map
service_frequency_map <- lga_vic_map %>%
  left_join(service_frequency_lga, by = c("LGA_CODE25", "LGA_NAME25"))

# Replace missing values with 0
service_frequency_map$service_frequency[is.na(service_frequency_map$service_frequency)] <- 0

# Plot the map
q2_p2 <- ggplot(service_frequency_map) +
  geom_sf(aes(fill = service_frequency), color = "grey", size = 0.1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Service frequency across LGAs in Victoria",
    subtitle = "Number of unique trips in each LGA",
    fill = "Service frequency"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

q2_p2

# Question 2
# mode variety

# Count the number of transport modes in each LGA
mode_variety_lga <- all_stops_lga %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(
    mode_variety = n_distinct(mode),
    .groups = "drop"
  )

# Join back to the LGA map
mode_variety_map <- lga_vic_map %>%
  left_join(mode_variety_lga, by = c("LGA_CODE25", "LGA_NAME25"))

# Replace missing values with 0
mode_variety_map$mode_variety[is.na(mode_variety_map$mode_variety)] <- 0

# Plot the map
q2_p3 <- ggplot(mode_variety_map) +
  geom_sf(aes(fill = mode_variety), color = "grey", size = 0.1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Transport mode variety across LGAs in Victoria",
    subtitle = "Number of transport modes in each LGA",
    fill = "Mode variety"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )





# Question 2
# service hours

# Create a function to convert HH:MM:SS to numeric hours
time_to_hours <- function(time_value) {
  time_value <- as.character(time_value)
  parts <- strsplit(time_value, ":")
  
  sapply(parts, function(x) {
    as.numeric(x[1]) + as.numeric(x[2]) / 60 + as.numeric(x[3]) / 3600
  })
}

# Match each service record to an LGA
service_hours_data <- all_time_data %>%
  left_join(
    all_stops_lga %>% select(mode, stop_id, LGA_CODE25, LGA_NAME25),
    by = c("mode", "stop_id")
  ) %>%
  filter(!is.na(LGA_CODE25)) %>%
  mutate(
    departure_hour = time_to_hours(departure_time)
  )

# Calculate earliest and latest service time in each LGA
service_hours_lga <- service_hours_data %>%
  group_by(LGA_CODE25, LGA_NAME25) %>%
  summarise(
    earliest_departure = min(departure_hour, na.rm = TRUE),
    latest_departure = max(departure_hour, na.rm = TRUE),
    service_hours = latest_departure - earliest_departure,
    .groups = "drop"
  )

# Join back to the LGA map
service_hours_map <- lga_vic_map %>%
  left_join(service_hours_lga, by = c("LGA_CODE25", "LGA_NAME25"))

# Replace missing values with 0
service_hours_map$service_hours[is.na(service_hours_map$service_hours)] <- 0

# Plot the map
q2_p4 <- ggplot(service_hours_map) +
  geom_sf(aes(fill = service_hours), color = "grey", size = 0.1) +
  scale_fill_gradient(
    low = "lightblue",
    high = "darkblue"
  ) +
  labs(
    title = "Service hours across LGAs in Victoria",
    subtitle = "Time span between earliest and latest departures in each LGA",
    fill = "Service hours"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    plot.subtitle = element_text(size = 11)
  )

q2_p4
#Combined map
combined_map <- (q2_p1 + q2_p2) / (q2_p3 + q2_p4)
combined_map


# Question 3
q3_data <- stop_density_map %>%
  st_drop_geometry() %>%
  select(LGA_CODE25, LGA_NAME25, stop_count, stop_density)

q3_data <- q3_data %>%
  left_join(
    service_frequency_map %>%
      st_drop_geometry() %>%
      select(LGA_CODE25, service_frequency),
    by = "LGA_CODE25"
  )

q3_data <- q3_data %>%
  left_join(
    mode_variety_map %>%
      st_drop_geometry() %>%
      select(LGA_CODE25, mode_variety),
    by = "LGA_CODE25"
  )

q3_data <- q3_data %>%
  left_join(
    service_hours_map %>%
      st_drop_geometry() %>%
      select(LGA_CODE25, service_hours),
    by = "LGA_CODE25"
  )

head(q3_data)

p_q3 <- ggplot(q3_data, aes(
  x = stop_count,
  y = service_frequency,
  color = mode_variety,
  size = service_hours
)) +
  geom_point(alpha = 0.8) +
  geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 0.7) +
  labs(
    title = "Service concentration and spatial reach across LGAs in Victoria",
    x = "Spatial reach (number of stops)",
    y = "Service concentration (number of unique trips)",
    color = "Mode variety",
    size = "Service hours"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold")
  )

p_q3



# Read the national LGA shapefile
lga_raw <- st_read("lga_data/LGA_2025_AUST_GDA2020.shp", quiet = TRUE)

# Plot the national LGA map
ggplot(lga_raw) +
  geom_sf(fill = "lightblue", color = "grey", size = 0.1) +
  labs(
    title = "National LGA boundary check",
    subtitle = "Australia-wide LGA boundaries",
    x = NULL,
    y = NULL
  ) +
  theme_minimal()

combined_plot <- q2_p1 + q2_p3 + q2_p4
combined_plot
