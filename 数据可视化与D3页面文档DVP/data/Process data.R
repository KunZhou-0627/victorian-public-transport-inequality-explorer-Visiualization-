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
library(purrr)
library(stringr)

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


feed_info <- data.frame(
  feed = c(
    "regional_train",
    "metropolitan_train",
    "metropolitan_tram",
    "myki_bus",
    "regional_coach",
    "regional_bus",
    "interstate_train",
    "skybus"
  ),
  
  folder = c(
    "gtfs_outer/regional_train",
    "gtfs_outer/metropolitan_train",
    "gtfs_outer/metropolitan_tram",
    "gtfs_outer/myki_bus",
    "gtfs_outer/regional_coach",
    "gtfs_outer/regional_bus",
    "gtfs_outer/interstate_train",
    "gtfs_outer/skybus"
  ),
  
  mode = c(
    "Train",
    "Train",
    "Tram",
    "Bus",
    "Bus",
    "Bus",
    "Train",
    "Bus"
  )
)


stops_test <- read_csv(
  one_stop_path,
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
) %>%
  clean_names()

glimpse(stops_test)



# Read and combine all stops.txt files


stops_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  stop_file <- file.path(current_folder, "stops.txt")
  
  message("Reading stops from: ", current_feed)
  
  if (file.exists(stop_file)) {
    
    stops_temp <- read_csv(
      stop_file,
      col_types = cols(.default = col_character()),
      show_col_types = FALSE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep the original GTFS stop_id
        stop_id_original = stop_id,
        
        # Create a new unique stop_id across all GTFS feeds
        stop_id = paste(feed, stop_id_original, sep = "__"),
        
        # Convert coordinates from character to numeric
        stop_lat = as.numeric(stop_lat),
        stop_lon = as.numeric(stop_lon)
      ) %>%
      select(
        feed,
        mode,
        stop_id,
        stop_id_original,
        stop_name,
        stop_lat,
        stop_lon,
        everything()
      )
    
    stops_list[[current_feed]] <- stops_temp
    
  } else {
    
    warning("Cannot find stops.txt in: ", current_folder)
    
  }
}
stops_all <- bind_rows(stops_list)
stops_all <- stops_all %>%
  filter(
    !is.na(stop_lat),
    !is.na(stop_lon)
  )
glimpse(stops_all)
stops_all %>%
  count(feed, mode)
stops_all %>%
  summarise(
    total_rows = n(),
    unique_stops = n_distinct(stop_id),
    missing_lat = sum(is.na(stop_lat)),
    missing_lon = sum(is.na(stop_lon))
  )

routes_test <- read_csv(
  one_route_path,
  col_types = cols(.default = col_character()),
  show_col_types = FALSE
) %>%
  clean_names()

glimpse(routes_test)


# Read and combine all routes.txt files


routes_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  route_file <- file.path(current_folder, "routes.txt")
  
  message("Reading routes from: ", current_feed)
  
  if (file.exists(route_file)) {
    
    routes_temp <- read_csv(
      route_file,
      col_types = cols(.default = col_character()),
      show_col_types = FALSE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep the original GTFS route_id
        route_id_original = route_id,
        
        # Create a new unique route_id across all GTFS feeds
        route_id = paste(feed, route_id_original, sep = "__"),
        
        # Convert route_type to integer
        route_type = as.integer(route_type)
      ) %>%
      select(
        feed,
        mode,
        route_id,
        route_id_original,
        route_short_name,
        route_long_name,
        route_type,
        everything()
      )
    
    routes_list[[current_feed]] <- routes_temp
    
  } else {
    
    warning("Cannot find routes.txt in: ", current_folder)
    
  }
}
routes_all <- bind_rows(routes_list)

routes_all %>%
  count(feed, mode)

routes_all %>%
  count(feed, mode, route_type)

routes_all %>%
  summarise(
    total_rows = n(),
    unique_routes = n_distinct(route_id),
    missing_route_id = sum(is.na(route_id)),
    missing_route_type = sum(is.na(route_type))
  )



# Read and combine all trips.txt files


trips_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  trip_file <- file.path(current_folder, "trips.txt")
  
  message("Reading trips from: ", current_feed)
  
  if (file.exists(trip_file)) {
    
    trips_temp <- read_csv(
      trip_file,
      col_types = cols(.default = col_character()),
      show_col_types = FALSE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep original GTFS IDs
        trip_id_original = trip_id,
        route_id_original = route_id,
        service_id_original = service_id,
        
        # Create unique IDs across GTFS feeds
        trip_id = paste(feed, trip_id_original, sep = "__"),
        route_id = paste(feed, route_id_original, sep = "__"),
        service_id = paste(feed, service_id_original, sep = "__")
      ) %>%
      select(
        feed,
        mode,
        trip_id,
        trip_id_original,
        route_id,
        route_id_original,
        service_id,
        service_id_original,
        everything()
      )
    
    trips_list[[current_feed]] <- trips_temp
    
  } else {
    
    warning("Cannot find trips.txt in: ", current_folder)
    
  }
}
trips_all <- bind_rows(trips_list)

trips_all %>%
  count(feed, mode)

trips_all %>%
  summarise(
    total_rows = n(),
    unique_trips = n_distinct(trip_id),
    unique_routes = n_distinct(route_id),
    unique_services = n_distinct(service_id),
    missing_trip_id = sum(is.na(trip_id)),
    missing_route_id = sum(is.na(route_id)),
    missing_service_id = sum(is.na(service_id))
  )




trips_route_check <- trips_all %>%
  left_join(
    routes_all %>%
      select(feed, route_id, route_short_name, route_long_name, route_type),
    by = c("feed", "route_id")
  )

trips_route_check %>%
  summarise(
    total_trips = n(),
    missing_route_match = sum(is.na(route_type))
  )



# Read and combine all calendar.txt files


calendar_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  calendar_file <- file.path(current_folder, "calendar.txt")
  
  message("Reading calendar from: ", current_feed)
  
  if (file.exists(calendar_file)) {
    
    calendar_temp <- read_csv(
      calendar_file,
      col_types = cols(.default = col_character()),
      show_col_types = FALSE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep original GTFS service_id
        service_id_original = service_id,
        
        # Create unique service_id across GTFS feeds
        service_id = paste(feed, service_id_original, sep = "__"),
        
        # Convert weekday flags to integer
        monday = as.integer(monday),
        tuesday = as.integer(tuesday),
        wednesday = as.integer(wednesday),
        thursday = as.integer(thursday),
        friday = as.integer(friday),
        saturday = as.integer(saturday),
        sunday = as.integer(sunday),
        
        # Convert dates
        start_date = as.Date(start_date, format = "%Y%m%d"),
        end_date = as.Date(end_date, format = "%Y%m%d")
      ) %>%
      select(
        feed,
        mode,
        service_id,
        service_id_original,
        monday,
        tuesday,
        wednesday,
        thursday,
        friday,
        saturday,
        sunday,
        start_date,
        end_date,
        everything()
      )
    
    calendar_list[[current_feed]] <- calendar_temp
    
  } else {
    
    warning("Cannot find calendar.txt in: ", current_folder)
    
  }
}
calendar_all <- bind_rows(calendar_list)
calendar_all %>%
  count(feed, mode)

calendar_all %>%
  summarise(
    total_rows = n(),
    unique_services = n_distinct(service_id),
    missing_service_id = sum(is.na(service_id)),
    min_start_date = min(start_date, na.rm = TRUE),
    max_end_date = max(end_date, na.rm = TRUE)
  )

calendar_all <- calendar_all %>%
  mutate(
    runs_weekday = if_else(
      monday == 1 | tuesday == 1 | wednesday == 1 | thursday == 1 | friday == 1,
      TRUE,
      FALSE
    ),
    runs_weekend = if_else(
      saturday == 1 | sunday == 1,
      TRUE,
      FALSE
    )
  )
calendar_all %>%
  count(feed, mode, runs_weekday, runs_weekend)


trips_calendar_check <- trips_all %>%
  left_join(
    calendar_all %>%
      select(
        feed,
        service_id,
        runs_weekday,
        runs_weekend,
        start_date,
        end_date
      ),
    by = c("feed", "service_id")
  )

trips_calendar_check %>%
  summarise(
    total_trips = n(),
    missing_calendar_match = sum(is.na(runs_weekday))
  )




# Read and combine all calendar_dates.txt files


calendar_dates_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  calendar_dates_file <- file.path(current_folder, "calendar_dates.txt")
  
  message("Reading calendar_dates from: ", current_feed)
  
  if (file.exists(calendar_dates_file)) {
    
    calendar_dates_temp <- read_csv(
      calendar_dates_file,
      col_types = cols(.default = col_character()),
      show_col_types = FALSE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep original GTFS service_id
        service_id_original = service_id,
        
        # Create unique service_id across GTFS feeds
        service_id = paste(feed, service_id_original, sep = "__"),
        
        # Convert date and exception type
        date = as.Date(date, format = "%Y%m%d"),
        exception_type = as.integer(exception_type)
      ) %>%
      select(
        feed,
        mode,
        service_id,
        service_id_original,
        date,
        exception_type,
        everything()
      )
    
    calendar_dates_list[[current_feed]] <- calendar_dates_temp
    
  } else {
    
    warning("Cannot find calendar_dates.txt in: ", current_folder)
    
  }
}
calendar_dates_all <- bind_rows(calendar_dates_list)
glimpse(calendar_dates_all)
calendar_dates_all %>%
  count(feed, mode)

calendar_dates_all %>%
  count(feed, mode, exception_type)


calendar_dates_all %>%
  summarise(
    total_rows = n(),
    unique_services = n_distinct(service_id),
    min_date = min(date, na.rm = TRUE),
    max_date = max(date, na.rm = TRUE),
    missing_service_id = sum(is.na(service_id)),
    missing_date = sum(is.na(date)),
    missing_exception_type = sum(is.na(exception_type))
  )


stop_times_test <- read_csv(
  one_stop_times_path,
  col_types = cols(.default = col_character()),
  show_col_types = FALSE,
  n_max = 10
) %>%
  clean_names()

glimpse(stop_times_test)


gtfs_time_to_hours <- function(x) {
  sapply(x, function(t) {
    
    if (is.na(t) || t == "") {
      return(NA_real_)
    }
    
    parts <- strsplit(t, ":", fixed = TRUE)[[1]]
    
    if (length(parts) != 3) {
      return(NA_real_)
    }
    
    hour <- suppressWarnings(as.numeric(parts[1]))
    minute <- suppressWarnings(as.numeric(parts[2]))
    second <- suppressWarnings(as.numeric(parts[3]))
    
    if (any(is.na(c(hour, minute, second)))) {
      return(NA_real_)
    }
    
    hour + minute / 60 + second / 3600
  })
}


# Read and combine all stop_times.txt files


stop_times_list <- list()

for (i in seq_len(nrow(feed_info))) {
  
  current_feed <- feed_info$feed[i]
  current_folder <- feed_info$folder[i]
  current_mode <- feed_info$mode[i]
  
  stop_times_file <- file.path(current_folder, "stop_times.txt")
  
  message("Reading stop_times from: ", current_feed)
  
  if (file.exists(stop_times_file)) {
    
    stop_times_temp <- read_csv(
      stop_times_file,
      col_types = cols_only(
        trip_id = col_character(),
        arrival_time = col_character(),
        departure_time = col_character(),
        stop_id = col_character(),
        stop_sequence = col_character()
      ),
      show_col_types = FALSE,
      progress = TRUE
    ) %>%
      clean_names() %>%
      mutate(
        feed = current_feed,
        mode = current_mode,
        
        # Keep original GTFS IDs
        trip_id_original = trip_id,
        stop_id_original = stop_id,
        
        # Create unique IDs across GTFS feeds
        trip_id = paste(feed, trip_id_original, sep = "__"),
        stop_id = paste(feed, stop_id_original, sep = "__"),
        
        # Convert sequence and time
        stop_sequence = as.integer(stop_sequence),
        arrival_hour = gtfs_time_to_hours(arrival_time),
        departure_hour = gtfs_time_to_hours(departure_time)
      ) %>%
      select(
        feed,
        mode,
        trip_id,
        trip_id_original,
        stop_id,
        stop_id_original,
        stop_sequence,
        arrival_time,
        departure_time,
        arrival_hour,
        departure_hour
      )
    
    stop_times_list[[current_feed]] <- stop_times_temp
    
  } else {
    
    warning("Cannot find stop_times.txt in: ", current_folder)
    
  }
}
stop_times_all <- bind_rows(stop_times_list)
glimpse(stop_times_all)

stop_times_all %>%
  count(feed, mode)


stop_times_all %>%
  summarise(
    total_rows = n(),
    unique_trips = n_distinct(trip_id),
    unique_stops = n_distinct(stop_id),
    missing_trip_id = sum(is.na(trip_id)),
    missing_stop_id = sum(is.na(stop_id)),
    missing_arrival_hour = sum(is.na(arrival_hour)),
    missing_departure_hour = sum(is.na(departure_hour))
  )

stop_times_trip_check <- stop_times_all %>%
  left_join(
    trips_all %>%
      select(feed, trip_id, route_id, service_id),
    by = c("feed", "trip_id")
  )

stop_times_trip_check %>%
  summarise(
    total_stop_times = n(),
    missing_trip_match = sum(is.na(route_id))
  )



# Create trip_info lookup table
# trips_all + routes_all + calendar_all


trip_info <- trips_all %>%
  select(
    feed,
    mode,
    trip_id,
    trip_id_original,
    route_id,
    route_id_original,
    service_id,
    service_id_original
  ) %>%
  left_join(
    routes_all %>%
      select(
        feed,
        route_id,
        route_short_name,
        route_long_name,
        route_type
      ),
    by = c("feed", "route_id")
  ) %>%
  left_join(
    calendar_all %>%
      select(
        feed,
        service_id,
        monday,
        tuesday,
        wednesday,
        thursday,
        friday,
        saturday,
        sunday,
        runs_weekday,
        runs_weekend,
        start_date,
        end_date
      ),
    by = c("feed", "service_id")
  )


trip_info %>%
  count(feed, mode, runs_weekday, runs_weekend)



# First, create a smaller lookup table

trip_info_small <- trip_info %>%
  select(
    feed,
    trip_id,
    route_id,
    route_short_name,
    route_long_name,
    route_type,
    service_id,
    runs_weekday,
    runs_weekend,
    start_date,
    end_date
  )

stops_small <- stops_all %>%
  select(
    feed,
    stop_id,
    stop_name,
    stop_lat,
    stop_lon
  )


# Merge to generate stop_events_all
stop_events_all <- stop_times_all %>%
  left_join(
    trip_info_small,
    by = c("feed", "trip_id")
  ) %>%
  left_join(
    stops_small,
    by = c("feed", "stop_id")
  )


stop_events_all %>%
  summarise(
    total_rows = n(),
    missing_route_id = sum(is.na(route_id)),
    missing_service_id = sum(is.na(service_id)),
    missing_calendar = sum(is.na(runs_weekday)),
    missing_stop_name = sum(is.na(stop_name)),
    missing_lat = sum(is.na(stop_lat)),
    missing_lon = sum(is.na(stop_lon))
  )



# Find LGA shapefile

lga_shp_path <- list.files(
  "lga_data",
  pattern = "\\.shp$",
  recursive = TRUE,
  full.names = TRUE
)

lga_shp_path



# Read LGA boundary data

lga_raw <- st_read(lga_shp_path[1], quiet = TRUE)

glimpse(lga_raw)



# Filter to Victoria LGAs only

lga_vic <- lga_raw %>%
  filter(STE_NAME21 == "Victoria") %>%
  transmute(
    lga_code = as.character(LGA_CODE25),
    lga_name = as.character(LGA_NAME25),
    area_sqkm = as.numeric(AREASQKM),
    geometry = geometry
  )

glimpse(lga_vic)

st_geometry_type(lga_vic) %>%
  table()



# Convert stops_all to sf points

stops_sf <- stops_all %>%
  filter(
    !is.na(stop_lon),
    !is.na(stop_lat)
  ) %>%
  st_as_sf(
    coords = c("stop_lon", "stop_lat"),
    crs = 4326,
    remove = FALSE
  )

glimpse(stops_sf)



# Transform stops to the same CRS as LGA polygons

stops_sf <- st_transform(stops_sf, st_crs(lga_vic))

st_crs(stops_sf)



# Spatial join: assign each stop to a Victorian LGA

stops_lga <- stops_sf %>%
  st_join(
    lga_vic %>%
      select(lga_code, lga_name, area_sqkm),
    join = st_within,
    left = TRUE
  )

stops_lga %>%
  st_drop_geometry() %>%
  summarise(
    total_stops = n(),
    matched_to_lga = sum(!is.na(lga_code)),
    not_matched_to_lga = sum(is.na(lga_code))
  )

stops_lga %>%
  st_drop_geometry() %>%
  filter(is.na(lga_code)) %>%
  count(feed, mode)


# Create non-spatial stop-to-LGA lookup table

stops_lga_table <- stops_lga %>%
  st_drop_geometry() %>%
  select(
    feed,
    mode,
    stop_id,
    stop_id_original,
    stop_name,
    stop_lat,
    stop_lon,
    lga_code,
    lga_name,
    area_sqkm
  )



# Add match method for initial spatial join

stops_lga <- stops_lga %>%
  mutate(
    lga_match_method = if_else(
      is.na(lga_code),
      "unmatched",
      "within_lga"
    )
  )


# Inspect unmatched stop coordinates

stops_lga %>%
  st_drop_geometry() %>%
  filter(is.na(lga_code)) %>%
  summarise(
    n_unmatched = n(),
    min_lat = min(stop_lat, na.rm = TRUE),
    max_lat = max(stop_lat, na.rm = TRUE),
    min_lon = min(stop_lon, na.rm = TRUE),
    max_lon = max(stop_lon, na.rm = TRUE)
  )



# Prepare projected data for nearest LGA matching

lga_vic_proj <- lga_vic %>%
  st_make_valid() %>%
  st_transform(3577)

stops_lga_proj <- stops_lga %>%
  st_transform(3577)

unmatched_stops <- stops_lga_proj %>%
  filter(is.na(lga_code))
nrow(unmatched_stops)


# Find nearest LGA for unmatched stops

nearest_lga_index <- st_nearest_feature(unmatched_stops, lga_vic_proj)

nearest_lga <- lga_vic_proj[nearest_lga_index, ] %>%
  st_drop_geometry() %>%
  select(
    nearest_lga_code = lga_code,
    nearest_lga_name = lga_name,
    nearest_area_sqkm = area_sqkm
  )

nearest_distance_m <- st_distance(
  unmatched_stops,
  lga_vic_proj[nearest_lga_index, ],
  by_element = TRUE
) %>%
  as.numeric()


unmatched_nearest_check <- unmatched_stops %>%
  st_drop_geometry() %>%
  select(
    feed,
    mode,
    stop_id,
    stop_id_original,
    stop_name,
    stop_lat,
    stop_lon
  ) %>%
  bind_cols(nearest_lga) %>%
  mutate(
    nearest_distance_m = nearest_distance_m
  )

unmatched_nearest_check %>%
  arrange(desc(nearest_distance_m)) %>%
  head(30)


# Apply nearest LGA match only if distance is within threshold

nearest_threshold_m <- 1000

nearest_lookup <- unmatched_nearest_check %>%
  mutate(
    lga_code_nearest = if_else(
      nearest_distance_m <= nearest_threshold_m,
      nearest_lga_code,
      NA_character_
    ),
    lga_name_nearest = if_else(
      nearest_distance_m <= nearest_threshold_m,
      nearest_lga_name,
      NA_character_
    ),
    area_sqkm_nearest = if_else(
      nearest_distance_m <= nearest_threshold_m,
      nearest_area_sqkm,
      NA_real_
    ),
    lga_match_method_nearest = if_else(
      nearest_distance_m <= nearest_threshold_m,
      "nearest_lga_within_1km",
      "outside_victoria_or_too_far"
    )
  ) %>%
  select(
    stop_id,
    lga_code_nearest,
    lga_name_nearest,
    area_sqkm_nearest,
    nearest_distance_m,
    lga_match_method_nearest
  )



# Update stops_lga with nearest LGA results

stops_lga_table <- stops_lga %>%
  st_drop_geometry() %>%
  left_join(
    nearest_lookup,
    by = "stop_id"
  ) %>%
  mutate(
    lga_code = coalesce(lga_code, lga_code_nearest),
    lga_name = coalesce(lga_name, lga_name_nearest),
    area_sqkm = coalesce(area_sqkm, area_sqkm_nearest),
    lga_match_method = case_when(
      lga_match_method == "within_lga" ~ "within_lga",
      !is.na(lga_code_nearest) ~ lga_match_method_nearest,
      TRUE ~ "outside_victoria_or_too_far"
    )
  ) %>%
  select(
    feed,
    mode,
    stop_id,
    stop_id_original,
    stop_name,
    stop_lat,
    stop_lon,
    lga_code,
    lga_name,
    area_sqkm,
    nearest_distance_m,
    lga_match_method
  )

stops_lga_table %>%
  summarise(
    total_stops = n(),
    matched_to_lga = sum(!is.na(lga_code)),
    not_matched_to_lga = sum(is.na(lga_code))
  )
stops_lga_table %>%
  count(mode, lga_match_method)
stops_lga_table %>%
  filter(is.na(lga_code)) %>%
  count(feed, mode)
stops_lga_table %>%
  filter(is.na(lga_code)) %>%
  select(feed, mode, stop_name, stop_lat, stop_lon, nearest_distance_m, lga_match_method) %>%
  arrange(desc(nearest_distance_m)) %>%
  head(30)



# Create stop-to-LGA lookup table

stop_lga_lookup <- stops_lga_table %>%
  select(
    feed,
    stop_id,
    lga_code,
    lga_name,
    area_sqkm,
    lga_match_method
  )


# Join LGA information back to stop events

stop_events_lga <- stop_events_all %>%
  left_join(
    stop_lga_lookup,
    by = c("feed", "stop_id")
  )



# Keep only stop events within Victorian LGAs

stop_events_vic <- stop_events_lga %>%
  filter(!is.na(lga_code))
stop_events_vic %>%
  summarise(
    total_stop_events = n(),
    unique_lgas = n_distinct(lga_code),
    unique_stops = n_distinct(stop_id),
    unique_trips = n_distinct(trip_id)
  )
stop_events_vic %>%
  count(mode)



# Save intermediate files

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

write_rds(stops_lga_table, "data/processed/stops_lga_table.rds")
write_rds(stop_events_vic, "data/processed/stop_events_vic.rds")


# Keep main public transport feeds for LGA-level analysis
# Exclude special services such as interstate train and SkyBus

analysis_feeds <- c(
  "regional_train",
  "metropolitan_train",
  "metropolitan_tram",
  "myki_bus",
  "regional_bus",
  "regional_coach"
)

stop_events_analysis <- stop_events_vic %>%
  filter(feed %in% analysis_feeds)



# LGA + mode level basic service indicators

lga_mode_basic <- stop_events_analysis %>%
  group_by(
    lga_code,
    lga_name,
    mode
  ) %>%
  summarise(
    n_stops = n_distinct(stop_id),
    n_routes = n_distinct(route_id),
    n_trips = n_distinct(trip_id),
    n_stop_events = n(),
    
    weekday_stop_events = sum(runs_weekday, na.rm = TRUE),
    weekend_stop_events = sum(runs_weekend, na.rm = TRUE),
    
    first_service_hour = min(departure_hour, na.rm = TRUE),
    last_service_hour = max(departure_hour, na.rm = TRUE),
    service_span_hours = last_service_hour - first_service_hour,
    
    .groups = "drop"
  )

lga_mode_basic %>%
  summarise(
    rows = n(),
    unique_lgas = n_distinct(lga_code),
    min_stops = min(n_stops, na.rm = TRUE),
    max_stops = max(n_stops, na.rm = TRUE),
    min_routes = min(n_routes, na.rm = TRUE),
    max_routes = max(n_routes, na.rm = TRUE),
    min_first_service = min(first_service_hour, na.rm = TRUE),
    max_last_service = max(last_service_hour, na.rm = TRUE)
  )

lga_mode_basic %>%
  group_by(mode) %>%
  slice_max(n_stop_events, n = 10) %>%
  ungroup() %>%
  select(
    mode,
    lga_name,
    n_stops,
    n_routes,
    n_trips,
    n_stop_events,
    first_service_hour,
    last_service_hour
  )



# Create full LGA x mode grid
# This ensures every Victorian LGA has Bus, Train, and Tram rows

lga_list <- lga_vic %>%
  st_drop_geometry() %>%
  select(
    lga_code,
    lga_name,
    area_sqkm
  )

mode_list <- tibble(
  mode = c("Bus", "Train", "Tram")
)

lga_mode_grid <- tidyr::crossing(
  lga_list,
  mode_list
)


# Join observed GTFS indicators onto full LGA x mode grid

lga_mode_complete <- lga_mode_grid %>%
  left_join(
    lga_mode_basic,
    by = c("lga_code", "lga_name", "mode")
  )

lga_mode_complete <- lga_mode_complete %>%
  mutate(
    n_stops = replace_na(n_stops, 0L),
    n_routes = replace_na(n_routes, 0L),
    n_trips = replace_na(n_trips, 0L),
    n_stop_events = replace_na(n_stop_events, 0L),
    weekday_stop_events = replace_na(weekday_stop_events, 0L),
    weekend_stop_events = replace_na(weekend_stop_events, 0L),
    
    service_span_hours = if_else(
      n_stop_events == 0,
      0,
      service_span_hours
    ),
    
    has_service = n_stop_events > 0
  )

lga_mode_complete %>%
  summarise(
    rows = n(),
    unique_lgas = n_distinct(lga_code),
    bus_rows = sum(mode == "Bus"),
    train_rows = sum(mode == "Train"),
    tram_rows = sum(mode == "Tram"),
    rows_with_service = sum(has_service),
    rows_without_service = sum(!has_service)
  )

lga_mode_complete %>%
  filter(!has_service) %>%
  count(mode)



# Create LGA-level indicators for all modes combined

lga_all_basic <- stop_events_analysis %>%
  group_by(
    lga_code,
    lga_name
  ) %>%
  summarise(
    mode = "All",
    
    n_stops = n_distinct(stop_id),
    n_routes = n_distinct(route_id),
    n_trips = n_distinct(trip_id),
    n_stop_events = n(),
    
    weekday_stop_events = sum(runs_weekday, na.rm = TRUE),
    weekend_stop_events = sum(runs_weekend, na.rm = TRUE),
    
    first_service_hour = min(departure_hour, na.rm = TRUE),
    last_service_hour = max(departure_hour, na.rm = TRUE),
    service_span_hours = last_service_hour - first_service_hour,
    
    .groups = "drop"
  )


# Complete all 82 LGAs for mode = All

lga_all_grid <- lga_list %>%
  mutate(
    mode = "All"
  )

lga_all_complete <- lga_all_grid %>%
  left_join(
    lga_all_basic,
    by = c("lga_code", "lga_name", "mode")
  )


# Replace missing All-mode service counts with 0

lga_all_complete <- lga_all_complete %>%
  mutate(
    n_stops = replace_na(n_stops, 0L),
    n_routes = replace_na(n_routes, 0L),
    n_trips = replace_na(n_trips, 0L),
    n_stop_events = replace_na(n_stop_events, 0L),
    weekday_stop_events = replace_na(weekday_stop_events, 0L),
    weekend_stop_events = replace_na(weekend_stop_events, 0L),
    
    service_span_hours = if_else(
      n_stop_events == 0,
      0,
      service_span_hours
    ),
    
    has_service = n_stop_events > 0
  )

lga_all_complete %>%
  summarise(
    rows = n(),
    unique_lgas = n_distinct(lga_code),
    rows_with_service = sum(has_service),
    rows_without_service = sum(!has_service)
  )


# Combine All + individual modes

lga_metrics_base <- bind_rows(
  lga_all_complete,
  lga_mode_complete
) %>%
  mutate(
    mode = factor(
      mode,
      levels = c("All", "Bus", "Train", "Tram")
    )
  ) %>%
  arrange(
    lga_name,
    mode
  ) %>%
  mutate(
    mode = as.character(mode)
  )


# Step 15A: Calculate mode diversity for each LGA

mode_diversity_lga <- lga_metrics_base %>%
  filter(mode %in% c("Bus", "Train", "Tram")) %>%
  group_by(lga_code, lga_name) %>%
  summarise(
    mode_count = sum(has_service),
    mode_diversity_score = mode_count / 3,
    mode_diversity_gap = 100 * (1 - mode_diversity_score),
    .groups = "drop"
  )


# Step 15A: Calculate mode diversity for each LGA

mode_diversity_lga <- lga_metrics_base %>%
  filter(mode %in% c("Bus", "Train", "Tram")) %>%
  group_by(
    lga_code,
    lga_name
  ) %>%
  summarise(
    mode_count = sum(has_service),
    
    # There are three possible modes in this project:
    # Bus, Train, Tram
    mode_diversity_score = mode_count / 3,
    
    # Higher gap means fewer mode choices
    mode_diversity_gap = 100 * (1 - mode_diversity_score),
    
    .groups = "drop"
  )

mode_diversity_lga %>%
  summarise(
    rows = n(),
    unique_lgas = n_distinct(lga_code),
    min_mode_count = min(mode_count, na.rm = TRUE),
    max_mode_count = max(mode_count, na.rm = TRUE),
    min_mode_diversity_gap = min(mode_diversity_gap, na.rm = TRUE),
    max_mode_diversity_gap = max(mode_diversity_gap, na.rm = TRUE)
  )


mode_diversity_lga %>%
  arrange(desc(mode_diversity_gap), lga_name) %>%
  select(
    lga_name,
    mode_count,
    mode_diversity_score,
    mode_diversity_gap
  ) %>%
  head(20)



# Step 15B.1: Join mode diversity back to LGA metrics

lga_metrics_scoring <- lga_metrics_base %>%
  left_join(
    mode_diversity_lga %>%
      select(
        lga_code,
        mode_count,
        mode_diversity_score,
        mode_diversity_gap
      ),
    by = "lga_code"
  )


# Step 15B.2: Create derived service indicators

lga_metrics_scoring <- lga_metrics_scoring %>%
  mutate(
    # Geographic stop density proxy
    stop_density = if_else(
      area_sqkm > 0,
      n_stops / area_sqkm,
      NA_real_
    ),
    
    # Route density proxy
    route_density = if_else(
      area_sqkm > 0,
      n_routes / area_sqkm,
      NA_real_
    ),
    
    # Average number of stop events per stop
    events_per_stop = if_else(
      n_stops > 0,
      n_stop_events / n_stops,
      0
    ),
    
    # Weekend service availability compared with weekday service
    weekend_weekday_ratio = case_when(
      weekday_stop_events > 0 ~ pmin(weekend_stop_events / weekday_stop_events, 1),
      weekday_stop_events == 0 & weekend_stop_events > 0 ~ 1,
      TRUE ~ 0
    )
  )



# Helper function for inverse gap score
# Higher service value = lower gap
# Lower service value = higher gap

make_inverse_gap <- function(x) {
  
  if (all(is.na(x))) {
    return(rep(NA_real_, length(x)))
  }
  
  x_min <- min(x, na.rm = TRUE)
  x_max <- max(x, na.rm = TRUE)
  
  if (x_max == x_min) {
    return(rep(0, length(x)))
  }
  
  gap <- 100 * (x_max - x) / (x_max - x_min)
  
  return(gap)
}



# Step 15B.5: Create gap scores

lga_metrics_scores <- lga_metrics_scoring %>%
  group_by(mode) %>%
  mutate(
    # Fewer stops per square km = higher coverage gap
    coverage_gap = make_inverse_gap(log1p(stop_density)),
    
    # Fewer stop events per stop = higher frequency gap
    frequency_gap = make_inverse_gap(log1p(events_per_stop)),
    
    # Shorter service span = higher service gap
    service_gap = make_inverse_gap(service_span_hours),
    
    # Lower weekend/weekday ratio = higher weekend gap
    weekend_weekday_gap = 100 * (1 - weekend_weekday_ratio),
    
    # No service means maximum gap for that mode
    coverage_gap = if_else(!has_service, 100, coverage_gap),
    frequency_gap = if_else(!has_service, 100, frequency_gap),
    service_gap = if_else(!has_service, 100, service_gap),
    weekend_weekday_gap = if_else(!has_service, 100, weekend_weekday_gap),
    
    # Overall inequality proxy score
    overall_score = (
      0.25 * coverage_gap +
        0.25 * frequency_gap +
        0.20 * service_gap +
        0.15 * weekend_weekday_gap +
        0.15 * mode_diversity_gap
    )
  ) %>%
  ungroup()


lga_metrics_scores %>%
  group_by(mode) %>%
  slice_max(overall_score, n = 10) %>%
  ungroup() %>%
  select(
    mode,
    lga_name,
    has_service,
    mode_count,
    n_stops,
    n_routes,
    n_stop_events,
    coverage_gap,
    frequency_gap,
    service_gap,
    weekend_weekday_gap,
    mode_diversity_gap,
    overall_score
  ) %>%
  arrange(mode, desc(overall_score))


# Remove non-standard LGA records

exclude_lgas <- c(
  "Migratory - Offshore - Shipping (Vic.)",
  "No usual address (Vic.)"
)

lga_metrics_base_clean <- lga_metrics_base %>%
  filter(!lga_name %in% exclude_lgas)

mode_diversity_lga_clean <- lga_metrics_base_clean %>%
  filter(mode %in% c("Bus", "Train", "Tram")) %>%
  group_by(
    lga_code,
    lga_name
  ) %>%
  summarise(
    mode_count = sum(has_service),
    mode_diversity_score = mode_count / 3,
    mode_diversity_gap = 100 * (1 - mode_diversity_score),
    .groups = "drop"
  )
mode_diversity_lga_clean %>%
  count(mode_count)




lga_metrics_scoring_clean <- lga_metrics_base_clean %>%
  left_join(
    mode_diversity_lga_clean %>%
      select(
        lga_code,
        mode_count,
        mode_diversity_score,
        mode_diversity_gap
      ),
    by = "lga_code"
  ) %>%
  mutate(
    stop_density = if_else(
      area_sqkm > 0,
      n_stops / area_sqkm,
      NA_real_
    ),
    
    route_density = if_else(
      area_sqkm > 0,
      n_routes / area_sqkm,
      NA_real_
    ),
    
    events_per_stop = if_else(
      n_stops > 0,
      n_stop_events / n_stops,
      0
    ),
    
    weekend_weekday_ratio = case_when(
      weekday_stop_events > 0 ~ pmin(weekend_stop_events / weekday_stop_events, 1),
      weekday_stop_events == 0 & weekend_stop_events > 0 ~ 1,
      TRUE ~ 0
    )
  )

lga_metrics_scores_clean <- lga_metrics_scoring_clean %>%
  group_by(mode) %>%
  mutate(
    coverage_gap = make_inverse_gap(log1p(stop_density)),
    
    frequency_gap = make_inverse_gap(log1p(events_per_stop)),
    
    service_gap = make_inverse_gap(service_span_hours),
    
    weekend_weekday_gap = 100 * (1 - weekend_weekday_ratio),
    
    coverage_gap = if_else(!has_service, 100, coverage_gap),
    frequency_gap = if_else(!has_service, 100, frequency_gap),
    service_gap = if_else(!has_service, 100, service_gap),
    weekend_weekday_gap = if_else(!has_service, 100, weekend_weekday_gap),
    
    overall_score = (
      0.25 * coverage_gap +
        0.25 * frequency_gap +
        0.20 * service_gap +
        0.15 * weekend_weekday_gap +
        0.15 * mode_diversity_gap
    )
  ) %>%
  ungroup()

lga_metrics_scores_clean %>%
  summarise(
    min_coverage_gap = min(coverage_gap, na.rm = TRUE),
    max_coverage_gap = max(coverage_gap, na.rm = TRUE),
    min_frequency_gap = min(frequency_gap, na.rm = TRUE),
    max_frequency_gap = max(frequency_gap, na.rm = TRUE),
    min_service_gap = min(service_gap, na.rm = TRUE),
    max_service_gap = max(service_gap, na.rm = TRUE),
    min_weekend_gap = min(weekend_weekday_gap, na.rm = TRUE),
    max_weekend_gap = max(weekend_weekday_gap, na.rm = TRUE),
    min_mode_diversity_gap = min(mode_diversity_gap, na.rm = TRUE),
    max_mode_diversity_gap = max(mode_diversity_gap, na.rm = TRUE),
    min_overall = min(overall_score, na.rm = TRUE),
    max_overall = max(overall_score, na.rm = TRUE)
  )

lga_metrics_scores_clean %>%
  group_by(mode) %>%
  slice_max(overall_score, n = 10, with_ties = FALSE) %>%
  ungroup() %>%
  select(
    mode,
    lga_name,
    has_service,
    mode_count,
    n_stops,
    n_routes,
    n_stop_events,
    coverage_gap,
    frequency_gap,
    service_gap,
    weekend_weekday_gap,
    mode_diversity_gap,
    overall_score
  ) %>%
  arrange(mode, desc(overall_score)) %>%
  print(n = 40, width = Inf)



# Final score adjustment
# If a specific mode has no service in an LGA, set overall score to 100

lga_metrics_final <- lga_metrics_scores_clean %>%
  mutate(
    overall_score = if_else(
      mode %in% c("Bus", "Train", "Tram") & !has_service,
      100,
      overall_score
    )
  )



# Step 16.2: Keep columns needed by D3

lga_metrics_d3 <- lga_metrics_final %>%
  transmute(
    lga_code,
    lga_name,
    area_sqkm,
    mode,
    
    has_service,
    mode_count,
    
    n_stops,
    n_routes,
    n_trips,
    n_stop_events,
    weekday_stop_events,
    weekend_stop_events,
    
    first_service_hour,
    last_service_hour,
    service_span_hours,
    
    stop_density,
    route_density,
    events_per_stop,
    weekend_weekday_ratio,
    
    coverage_gap,
    frequency_gap,
    service_gap,
    weekend_weekday_gap,
    mode_diversity_gap,
    overall_score
  )



# Step 16.3: Export LGA metrics for D3

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

write_csv(
  lga_metrics_d3,
  "data/processed/lga_metrics.csv"
)



# Clean LGA boundary for D3 map

lga_vic_clean <- lga_vic %>%
  filter(!lga_name %in% exclude_lgas)


# Step: Simplify and export GeoJSON for D3

lga_vic_geojson <- lga_vic_clean %>%
  st_make_valid() %>%
  st_transform(7855) %>%
  st_simplify(dTolerance = 200, preserveTopology = TRUE) %>%
  st_transform(4326)

st_write(
  lga_vic_geojson,
  "data/processed/vic_lga_2025_simplified.geojson",
  driver = "GeoJSON",
  delete_dsn = TRUE,
  quiet = TRUE
)



# Step 18: Check CSV and GeoJSON consistency

metrics_lgas <- lga_metrics_d3 %>%
  distinct(lga_code, lga_name)

boundary_lgas <- lga_vic_clean %>%
  st_drop_geometry() %>%
  distinct(lga_code, lga_name)

anti_join(metrics_lgas, boundary_lgas, by = "lga_code")

anti_join(boundary_lgas, metrics_lgas, by = "lga_code")
