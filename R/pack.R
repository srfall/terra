

setClass("PackedSpatVector",
	representation (
		type = "character",
		crs = "character",
		coordinates = "matrix",
		index = "matrix",
		attributes = "data.frame"
	),
	prototype (
		type= "",
		crs = ""
	)
)


setClass("PackedSpatRaster",
	representation (
		definition = "character",
		values = "matrix",
		attributes = "list"
	),
	prototype (
		attributes = list()
	)
)



setMethod("wrap", signature(x="SpatVector"),
	function(x) {
		vd <- methods::new("PackedSpatVector")
		vd@type <- geomtype(x)
		vd@crs <- as.character(crs(x))
		#stopifnot(vd@type %in% c("points", "lines", "polygons"))
		g <- geom(x)
		vd@coordinates <- g[, c("x", "y"), drop=FALSE]
		j <- c(1, 2, grep("hole", colnames(g)))
		g <- g[ , j, drop=FALSE]
		i <- which(!duplicated(g))
		vd@index <- cbind(g[i, ,drop=FALSE], start=i)
		vd@attributes <- as.data.frame(x)
		vd
	}
)


setMethod("unwrap", signature(x="PackedSpatVector"),
	function(x) {
		p <- methods::new("SpatVector")
		p@ptr <- SpatVector$new()
		if (!is.na(x@crs)) {
			crs(p, warn=FALSE) <- x@crs
		}
		if (nrow(x@coordinates) == 0) {
			return(p)
		}

		n <- ncol(x@index)
		reps <- diff(c(x@index[,n], nrow(x@coordinates)+1))
		i <- rep(1:nrow(x@index), reps)
		if (n == 2) {
			p@ptr$setGeometry(x@type, x@index[i,1], x@index[i,2], x@coordinates[,1], x@coordinates[,2], rep(0, nrow(x@coordinates)))
		} else {
			p@ptr$setGeometry(x@type, x@index[i,1], x@index[i,2], x@coordinates[,1], x@coordinates[,2], x@index[i,3])
		}
		if (nrow(x@attributes) > 0) {
			values(p) <- x@attributes
		}
		messages(p, "pack")
	}
)

setMethod("vect", signature(x="PackedSpatVector"),
	function(x) {
		unwrap(x)
	}
)


setMethod("show", signature(object="PackedSpatVector"),
	function(object) {
		print(paste("This is a", class(object), "object. Use 'terra::unwrap()' to unpack it"))
	}
)



setMethod("as.character", signature(x="SpatRaster"),
	function(x) {
		e <- as.vector(ext(x))
		d <- crs(x, describe=TRUE)
		if (!(is.na(d$authority) || is.na(d$code))) {
			crs <- paste0(", crs='", d$authority, ":", d$code, "'")
		} else {
			d <- crs(x)
			crs <- ifelse(d=="", ", crs=''", paste0(", crs='", d, "'"))
			crs <- gsub("\n[ ]+", "", crs)
		}
		nms <- paste0(", names=c('", paste(names(x), collapse="', '"), "')")
		paste0("rast(",
				"ncols=", ncol(x),
				", nrows=", nrow(x),
				", nlyrs=", nlyr(x),
				", xmin=",e[1],
				", xmax=",e[2],
				", ymin=",e[3],
				", ymax=",e[4],
				nms,
				crs, ")"
		)
	}
)
#eval(parse(text=as.character(s)))


setMethod("wrap", signature(x="SpatRaster"),
	function(x, proxy=FALSE) {
		r <- methods::new("PackedSpatRaster")
		r@definition <- as.character(x)

		opt <- spatOptions(ncopies=2)
		can <- (!proxy) && x@ptr$canProcessInMemory(opt)

		s <- sources(x)
		if (can || (all(s == ""))) {
			r@values <- values(x)
		} else if (all(s != "")) {
			r@attributes$sources <- sources(x, TRUE, TRUE)
		} else {
			fname <- paste0(tempfile(), ".tif")
			x <- writeRaster(x, fname)
			r@attributes$filename <- fname
		}

		if (any(is.factor(x))) {
			r@attributes$levels <- cats(x)
			r@attributes$levindex <- activeCat(x, 0)
		}
		v <- time(x)
		if (any(!is.na(v))) {
			r@attributes$time <- v
		}
		v <- units(x)
		if (all(v != "")) {
			r@attributes$units <- v
		}
		v <- depth(x)
		if (!all(v ==0)) {
			r@attributes$depth <- v
		}
		r
	}
)


setMethod("unwrap", signature(x="PackedSpatRaster"),
	function(x) {

		r <- eval(parse(text=x@definition))
		if (!is.null(x@attributes$filename)) {
			rr <- rast(x@attributes$filename)
			ext(rr) <- ext(r)
			crs(rr, warn=FALSE) <- crs(r)
			r <- rr
		} else if (!is.null(x@attributes$sources)) {
			s <- x@attributes$sources
			u <- unique(s$sid)
			rr <- lapply(1:length(u), function(i) {
					ss <- s[s$sid == i, ]
					r <- rast(ss[1,2])
					r[[ss[,3]]]
				})
			rr <- rast(rr)
			ext(rr) <- ext(r)
			crs(rr, warn=FALSE) <- crs(r)
			r <- rr
		} else {
			values(r) <- x@values
		}

		if (length(x@attributes) > 0) {
			nms <- names(x@attributes)
			if (any(nms %in% c("levels", "time", "units", "depth"))) {
				time(r) <- x@attributes$time
				units(r) <- x@attributes$units	
				depth(r) <- x@attributes$depth
				if (!is.null(x@attributes$levels)) {
					if (is.null(x@attributes$levindex)) x@attributes$levindex <- 1
					set.cats(r, layer=0, x@attributes$levels, active=x@attributes$levindex)
				}
			}
		}
		r
	}
)

setMethod("rast", signature(x="PackedSpatRaster"),
	function(x) {
		unwrap(x)
	}
)

setMethod("show", signature(object="PackedSpatRaster"),
	function(object) {
		print(paste("This is a", class(object), "object. Use 'terra::unwrap()' to unpack it"))
	}
)




setMethod("unwrap", signature(x="ANY"),
	function(x) {
		x
	}
)


setMethod("serialize", signature(object="SpatVector"),
	function(object, connection, ascii = FALSE, xdr = TRUE, version = NULL, refhook = NULL) {
		object = wrap(object)
		serialize(object, connection=connection, ascii = ascii, xdr = xdr, version = version, refhook = refhook)
	}
)


setMethod("saveRDS", signature(object="SpatVector"),
	function(object, file="", ascii = FALSE, version = NULL, compress=TRUE, refhook = NULL) {
		object = wrap(object)
		saveRDS(object, file=file, ascii = ascii, version = version, compress=compress, refhook = refhook)
	}
)


setMethod("serialize", signature(object="SpatRaster"),
	function(object, connection, ascii = FALSE, xdr = TRUE, version = NULL, refhook = NULL) {
		object <- wrap(object, proxy=TRUE)
		serialize(object, connection=connection, ascii = ascii, xdr = xdr, version = version, refhook = refhook)
	}
)

setMethod("unserialize", signature(connection="ANY"),
	function(connection, refhook = NULL) {
		x <- base::unserialize(connection, refhook)
		unwrap(x)
	}
)


setMethod("saveRDS", signature(object="SpatRaster"),
	function(object, file="", ascii = FALSE, version = NULL, compress=TRUE, refhook = NULL) {
		object <- wrap(object)
		saveRDS(object, file=file, ascii = ascii, version = version, compress=compress, refhook = refhook)
	}
)



setMethod("readRDS", signature(file="character"),
	function (file = "", refhook = NULL) {
		x <- base::readRDS(file=file, refhook=refhook)
		unwrap(x)
	}
)



#setMethod("wrap", signature(x="Spatial"),
#	function(x) {
#		pv <- .packVector(x)
#		if (methods::.hasSlot(x, "data")) {
#			pv@attributes <- x@data
#		}
#		pv
#	}
#)
