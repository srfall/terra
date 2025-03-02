# Author: Robert J. Hijmans
# Date:  October 2018
# Version 1.0
# License GPL v3


format_ym <- function(x) {
	y <- floor(x)
	m <- round((x-y) * 12 + 1)
	m <- month.abb[m]
	paste(y, m, sep="-")
}

yearweek <- function(d) {
	y <- as.integer(strftime(d, format = "%Y"))
	w <- strftime(d, format = "%V")
	m <- strftime(d, format = "%m")
	i <- w > "51" & m=="01"
	y[i] <- y[i] - 1
	i <- w=="01" & m=="12"
	y[i] <- y[i] + 1
	yy <- as.character(y)
	i <- nchar(yy) < 4
	yy[i] <- formatC(y[i], width=4, flag="0")	
	paste0(yy, w)
}


setMethod("timeInfo", signature(x="SpatRaster"),
	function(x) {
		time <- x@ptr$hasTime
		if (time) {
			step <- x@ptr$timestep
			if (step == "seconds") {
				data.frame(time=time, step=step, zone=x@ptr$timezone)
			} else {
				data.frame(time=time, step=step, zone="")
			}
		} else {
			data.frame(time=time, step="", zone="")
		}
	}
)


time_as_seconds <- function(x) {
	d <- x@ptr$time
	d <- strptime("1970-01-01", "%Y-%m-%d", tz="UTC") + d
	tz <- x@ptr$timezone
	if (!(tz %in% c("", "UTC"))) {
		attr(d, "tzone") = tz
	}
	d
}


setMethod("time", signature(x="SpatRaster"),
	function(x, format="") {
		if (!x@ptr$hasTime) {
			return(rep(NA, nlyr(x)))
		}
		d <- x@ptr$time
		tstep <- x@ptr$timestep
		if (format != "") {
			if ((format == "months") && (tstep == "years")) {
				error("time", "cannot extract months from years-time")
			} else if ((format == "years") && (tstep %in% c("months"))) {
				error("time", "cannot extract years from months-time")
			} else if ((format == "yearmonthis") && (tstep %in% c("months", "years"))) {
				error("time", "cannot extract yearmon from this type of time data")
			} else if ((format == "seconds") && (tstep != "seconds")) {
				error("time", "cannot extract seconds from this type of time data")
			} else if ((format == "days") && (!(tstep %in% c("seconds", "days")))) {
				error("time", "cannot extract days from this type of time data")
			}
			tstep <- format
		} else {
			tstep <- x@ptr$timestep
		}
		if (tstep == "seconds") {
			d <- strptime("1970-01-01", "%Y-%m-%d", tz="UTC") + d
			tz <- x@ptr$timezone
			if (!(tz %in% c("", "UTC"))) {
				attr(d, "tzone") = tz
			}
			d
		} else if (tstep == "days") {
			d <- strptime("1970-01-01", "%Y-%m-%d", tz = "UTC") + d
			as.Date(d)
		} else if (tstep == "yearmonths") {
			d <- strptime("1970-01-01", "%Y-%m-%d", tz = "UTC") + d
			y <- as.integer(format(d, "%Y"))
			y + (as.integer(format(d, "%m"))-1)/12
		} else if (tstep == "months") {
			d <- strptime("1970-01-01", "%Y-%m-%d", tz = "UTC") + d
			as.integer(format(d, "%m"))
		} else if (tstep == "years") {
			d <- strptime("1970-01-01", "%Y-%m-%d", tz = "UTC") + d
			as.integer(format(d, "%Y"))
		} else { # raw
			d
		}
	}
)

posix_from_ym <- function(y, m) {
	y <- floor(y)
	i <- ((y < 0) | (y > 9999))
	if (any(i)) {
		d <- paste(paste(rep("1900", length(y)), m, "15", sep="-"), "12:00:00")
		d[!i] <- paste(paste(y[!i], m, "15", sep="-"), "12:00:00")
		d <- as.POSIXlt(d, format="%Y-%m-%d %H:%M:%S", tz="UTC")
		for (j in i) {
			d$year[j] = y[j] - 1900
		}
		d
	} else {
		d <- paste(paste(y, m, "15", sep="-"), "12:00:00")
		as.POSIXlt(d, format="%Y-%m-%d %H:%M:%S", tz="UTC")
	}
}


setMethod("time<-", signature(x="SpatRaster"),
	function(x, tstep="", value)  {
		if (missing(value)) {
			value <- tstep
			tstep <- ""
		}
		if (is.null(value)) {
			x@ptr$setTime(0[0], "remove", "")
			return(x)
		}
		if (inherits(value, "character")) {
			error("time<-", "value cannot be a character type")
		}
		if (length(value) != nlyr(x)) {
			error("time<-", "length(value) != nlyr(x)")
		}
		if (tstep != "") {
			tstep = match.arg(as.character(tstep), c("days", "months", "years", "yearmonths", "raw"))
		}
		
		tzone <- "UTC"
		stept <- ""
		if (inherits(value, "Date")) {
			value <- as.POSIXlt(value)
			if (tstep == "") stept <- "days"
		} else if (inherits(value, "POSIXt")) {
			if (tstep == "") stept <- "seconds"
			tzone <- attr(value, "tzone")
			if (is.null(tzone)) tzone = ""
		} else if (inherits(value, "yearmon")) {
			value <- as.numeric(value)
			year <- floor(value)
			month <- round(12 * (value - year) + 1)
			value <- posix_from_ym(value, month)
			if (tstep == "") stept <- "yearmonths"
		} 
		
		if (stept == "") {
			stept = tstep
			if (tstep == "years") {
				if (is.numeric(value)) {
					value <- posix_from_ym(value, "6")
				} else {
					value <- as.integer(strftime(value, format = "%Y"))
					value <- posix_from_ym(value, "6")
				}
			} else if (tstep == "months") {
				if (is.numeric(value)) {
					value <- floor(value)
				} else {
					value <- as.integer(strftime(value, format = "%m"))
				}
				if (!all(value %in% 1:12)) {
					error("date<-", "months should be between 1 and 12")
				}
				value <- posix_from_ym(1970, value)
			} else if (tstep == "yearmonths") {
				if (is.numeric(value)) {
					y <- round(value, -2)
					m <- value - (y * 100)
				} else {
					y <- as.integer(strftime(value, format = "%Y"))
					m <- as.integer(strftime(value, format = "%m"))
				}
				if (!all(m %in% 1:12)) {
					error("date<-", "months should be between 1 and 12")
				}
				value <- posix_from_ym(y, m)
			#} else if (tstep == "days") {
			#	print(value)
			#	value <- as.Date(value)
			#	stept = tstep
			} else if (tstep == "") {
				stept <- "raw"
			}
		}
		if (!x@ptr$setTime(as.numeric(value), stept, tzone)) {
			error("time<-", "cannot set these values")
		}
		return(x)
	}
)



setMethod("depth", signature(x="SpatRaster"),
	function(x) {
		x@ptr$depth
	}
)


setMethod("depth<-", signature(x="SpatRaster"),
	function(x, value)  {
		if (is.null(value)) {
			x@ptr$setDepth(0[0])
			return(x)
		}
		value <- as.numeric(value)
		if (! x@ptr$setDepth(value)) {
			error("depth<-", "cannot set these  values")
		}
		return(x)
	}
)

setMethod("linearUnits", signature(x="SpatRaster"),
	function(x) {
		.getLinearUnits(crs(x))
	}
)

setMethod("linearUnits", signature(x="SpatVector"),
	function(x) {
		.getLinearUnits(crs(x))
	}
)

setMethod("units", signature(x="SpatRaster"),
	function(x) {
		x@ptr$units
	}
)

setMethod("units<-", signature(x="SpatRaster"),
	function(x, value)  {
		if (is.null(value) || all(is.na(value))) {
			value <- ""
		} else {
			value <- as.character(value)
		}
		if (! x@ptr$set_units(value)) {
			error("units<-", "cannot set these  values")
		}
		return(x)
	}
)


setMethod("units", signature(x="SpatRasterDataset"),
	function(x) {
		x@ptr$units
	}
)

setMethod("units<-", signature(x="SpatRasterDataset"),
	function(x, value)  {
		value <- as.character(value)
		x@ptr$units <- value
		return(x)
	}
)

