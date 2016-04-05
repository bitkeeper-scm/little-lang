#!/usr/bin/bk tclsh
/*
 * A rewrite of Eric Pop's fine igal program in L.  I talked to Eric and he
 * really doesn't want anything to do with supporting igal or copycats so
 * while credit here is cool, don't stick his name on the web pages.
 * I completely understand that, people still ask me about webroff and
 * lmbench.
 *
 * First version by Larry McVoy Sun Dec 19 2010.
 *
 * usage photos [options] [dir]
 *
 * TODO
 * - slideshow mode
 * - move the next/prev/index to the sides along w/ EXIF info
 */
int	bigy = 750;		// --bigy=%d for medium images
int	dates = 0;		// --date-split
int	exif = 0;		// --exif under titles
int	exif_hover = 0;		// --exif-hover, exif data in thumbnail hover
int	exif_thumbs = 0;	// --exif-thumbnails, use the camera thumbnail
int	force = 0;		// -f force regen of everything
int	names = 0;		// put names below the image
int	nav = 0;		// month/year nav
int	parallel = 1;		// -j%d for multiple processes
int	sharpen = 0;		// --sharpen to turn it on
int	thumbnails = 0;		// force regen of those
int	quiet = 1;		// turn off verbose
string	title = "McVoy photos";	// --title=whatever
int	ysize = 120;		// -ysize=%d for thumbnails
int	rotate[];		// amount to rotate, -+90
string	indexf = "~/.photos/index.html";
string	slidef = "~/.photos/slide.html";

int
main(int ac, string av[])
{
	string	c;
	string	lopts[] = {
		"bigy:",
		"date-split",
		"exif",
		"exif-thumbnails",
		"exif-hover",
		"force",
		"index:",
		"names",
		"nav",
		"parallel:",
		"quiet",
		"regen",
		"sharpen",
		"slide:",
		"thumbnails",
		"title:",
		"ysize:",
	};

	if (0) ac = 0;	// lint
	parallel = cpus();
	dotfiles();

	while (c = getopt(av, "fj:", lopts)) {
		switch (c) {
		    case "bigy": bigy = (int)optarg; break;
		    case "date-split": dates = 1; break;
		    case "exif": exif = 1; break;
		    case "exif-hover": exif_hover = 1; break;
		    case "exif-thumbnails": exif_thumbs = 1; break;
		    case "f":
		    case "force":
		    case "regen":
			force = 1; break;
		    case "index": indexf = optarg; break;
		    case "j":
		    case "parallel": parallel = (int)optarg; break;
		    case "quiet": quiet = 1; break;
		    case "names": names = 1; break;
		    case "nav": nav = 1; break;
		    case "sharpen": sharpen = 1; break;
		    case "slide": slidef = optarg; break;
		    case "title": title = optarg; break;
		    case "thumbnails": thumbnails = 1; break;
		    case "ysize": ysize = (int)optarg; break;
		    default: 
		    printf("Usage: photos.l");
		    foreach(c in lopts) {
			if (c =~ /(.*):/) {
			    printf(" --%s=<val>", $1);
			} else {
			    printf(" --%s", c);
			}
		    }
		    printf("\n");
		    return(0);
		}
	}
	unless (av[optind]) {
	    dir(".");
	} else {
	    while (av[optind]) dir(av[optind++]);
	}
	return (0);
}

void
dir(string d)
{
	string	jpegs[];
	string	tmp[];
	string	buf;
	int	i;

	if (chdir(d)) die("can't chdir to %s", d);
	tmp = getdir(".", "*.jpeg");
	unless (tmp[0]) tmp = getdir(".", "*.jpg");
	unless (tmp[0]) tmp = getdir(".", "*.png");
	unless (tmp[0]) tmp = getdir(".", "*.PNG");
	unless (tmp[0]) die("No jpegs found in %s", d);
	// XXX - should getdir do this?
	for (i = 0; defined(tmp[i]); i++) tmp[i] =~ s|^\./||;

	/* so we start at one not zero */
	jpegs[0] = '.';
	rotate[0] = 0;
	// XXX - I want push(&jpegs, list)
	foreach (buf in tmp) {
		push(&jpegs, buf);
		push(&rotate, rotation(buf));
	}

	slides(jpegs);
	thumbs(jpegs);
	html(jpegs);
}

/*
 * Create .thumb-$file if
 * - it does not exist
 * - .ysize is different than ysize
 * - $file is newer than thumbnail
 */
void
thumbs(string jpegs[])
{
	string	cmd[];
	string	jpeg, file, slide;
	int	i;
	int	all = 0;
	int	my_parallel = parallel, bg = 0;
	int	pid, reaped;
	int	pids{int};

	unless (exists(".ysize")) {
save:		Fprintf(".ysize", "%d\n", ysize);
	}
	if ((int)`cat .ysize` != ysize) {
		all = 1;
		goto save;
	}
	if (force || thumbnails) all = 1;
	if (exif_thumbs) my_parallel = 1;
	for (i = 1; defined(jpeg = jpegs[i]); i++) {
		file = sprintf(".thumb-%s", jpeg);
		slide = sprintf(".slide-%s", jpeg);
		if (!all && exists(file) && (mtime(file) > mtime(jpeg))) {
			continue;
		}

		if (exif_thumbs && do_exif(undef, jpeg)) {
			unlink(file);
			cmd = {
			    "exif",
			    "-e",
			    "-o", file,
			    jpeg
			};
		} else {
			cmd = {
			    "convert",
			    "-thumbnail",
			    "x${ysize}",
			    "-quality", "85",
			};
			if (sharpen) {
				push(&cmd, "-unsharp");
				//push(&cmd, "0x.5");
				push(&cmd, "2x0.5+0.7+0");
			}
			push(&cmd, exists(slide) ? slide : jpeg);
			push(&cmd, file);
		}
		while (bg >= parallel) {
			reaped = 0;
			foreach (pid in keys(pids)) {
				if (waitpid(pid, undef, 1) > 0) {
					reaped++;
					bg--;
					undef(pids{pid});
					break;
				}
			}
			if (reaped) break;
			sleep(0.100);
		}
		unless (quiet) {
			printf("Creating %s from %s\n",
			    file, exists(slide) ? slide : jpeg);
		}
		pid = spawn(cmd);
		unless (defined(stdio_status.path)) {
			die("%s: command not found.\n", cmd[0]);
		}
		bg++;
		pids{pid} = 1;
	}
	foreach (pid in keys(pids)) waitpid(pid, undef, 0);
}

/*
 * Create .slide-$file if
 * - it does not exist
 * - .bigy is different than bigy
 * - $file is newer than slide
 * - $file is bigger than bigy
 */
void
slides(string jpegs[])
{
	string	cmd[];
	string	jpeg, file;
	int	all = 0;
	int	i;
	int	bg = 0;
	int	pid, reaped;
	int	pids{int};

	unless (exists(".bigy")) {
save:		Fprintf(".bigy", "%d\n", bigy);
	}
	if ((int)`cat .bigy` != bigy) {
		all = 1;
		goto save;
	}
	if (force) all = 1;
	for (i = 1; defined(jpeg = jpegs[i]); i++) {
		file = sprintf(".slide-%s", jpeg);
		if (!all && exists(file) && (mtime(file) > mtime(jpeg))) {
			continue;
		}
		if (small(jpeg)) {
			unlink(file);
			if (link(jpeg, file)) warn("link ${jpeg} ${file}");
			continue;
		}
		cmd = {
		    "convert",
		    "+profile", "*",
		    "-scale", "x" . "${bigy}",
		    "-quality", "85",
		};
		if (rotate[i]) {
			push(&cmd, "-rotate");
			push(&cmd, sprintf("%d", rotate[i]));
		}
		if (sharpen) {
			push(&cmd, "-unsharp");
			//push(&cmd, "0x.5");
			push(&cmd, "2x0.5+0.7+0");
		}
		push(&cmd, jpeg);
		push(&cmd, file);
		while (bg >= parallel) {
			reaped = 0;
			foreach (pid in keys(pids)) {
				if (waitpid(pid, undef, 1) > 0) {
					reaped++;
					bg--;
					undef(pids{pid});
					break;
				}
			}
			if (reaped) break;
			sleep(0.150);
		}
		unless (quiet) {
			printf("Creating %s from %s\n", file, jpeg);
		}
		printf("%s\n", join(" ", cmd));
		pid = spawn(cmd);
		unless (defined(stdio_status.path)) {
			die("%s: command not found.\n", cmd[0]);
		}
		bg++;
		pids{pid} = 1;
	}
	foreach (pid in keys(pids)) waitpid(pid, undef, 0);
}

int
small(string file)
{
	string	buf;

	// Hack to avoid exif calls on small files
	if (size(file) < 100000) return (1);
	if (size(file) > 200000) return (0);
	unless (buf = `identify '${file}'`) return (0);
	if (buf =~ /JPEG (\d+)x(\d+)/) return ((int)$2 <= bigy);
	return (0);
}

string num2mon{int} = {
	1 => "January",
	2 => "February",
	3 => "March",
	4 => "April",
	5 => "May",
	6 => "June",
	7 => "July",
	8 => "August",
	9 => "September",
	10 => "October",
	11 => "November",
	12 => "December",
};

typedef	struct {
	int	day;	// day 1..31
	int	mon;	// month 1..12
	int	year;	// year as YYYY
	string	sdate;	// YYYY-MM-DD
} date;

/*
 * Return the date either from the filename if it is one of date ones,
 * or from the exif data,
 * or fall back to mtime.
 */
date
f2date(string file)
{
	date	d;
	string	buf;
	FILE	f;
	int	t;

	if (file =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/) {
match:		
		buf = (string)$3; buf =~ s/^0//; d.day = (int)buf;
		buf = (string)$2; buf =~ s/^0//; d.mon = (int)buf;
		d.year = (int)$1;
		d.sdate = sprintf("%d-%02d-%02d", d.year, d.mon, d.day);
		return (d);
	}

	if (f = popen("exif -t DateTime '${file}' 2>/dev/null", "r")) {
		while (buf = <f>) {
			// Value: 2006:02:04 22:59:24
			if (buf =~ /Value: (\d\d\d\d):(\d\d):(\d\d)/) {
				pclose(f);
				goto match;
			}
		}
		pclose(f);
		// fall through to mtime
	}

	if (t = mtime(file)) {
		buf = Clock_format(t, format: "%Y:%m:%d");
		buf =~ /(\d\d\d\d):(\d\d):(\d\d)/;
		goto match;
	}

	return (undef);
}

/*
 * Create the html slide files and index.html
 * XXX - could stub this out if mtime(html) > mtime(.slide) etc.
 */
void
html(string jpegs[])
{
	string	template, file, stitle, ntitle, ptitle, buf;
	string	cap = '';
	string	date_nav = '';
	string	dir, jpeg, escaped, thumbs = '';
	int	i, next, prev;
	int	first = 1;
	FILE	f;
	string	map[];
	string	exdata;
	date	d, d2;

	unless (f = fopen(slidef, "rv")) die("slide.html");
	read(f, &template, -1);
	fclose(f);

	for (i = 1; defined(jpeg = jpegs[i]); i++) {
		file = sprintf("%d.html", i);
		if (i > 1) {
			prev = i - 1;
		} else {
			prev = length(jpegs) - 1;
		}
		if (jpegs[i+1]) {
			next = i + 1;
		} else {
			next = 1;
		}
		undef(map);
		stitle = jpeg;
		stitle =~ s/\.jp.*//;
		ntitle = jpegs[next];
		ntitle =~ s/\.jp.*//;
		ptitle = jpegs[prev];
		ptitle =~ s/\.jp.*//;
		escaped = jpeg;
		escaped =~ s/:/%3A/g;
		dir = `pwd`;
		dir =~ s|.*/||;
		map = {
			"%FOLDER%",
			dir,
			"%TITLE%",
			stitle,
			"%NEXT_HTML%",
			sprintf("%d.html", next),
			"%NEXT_TITLE%",
			ntitle,
			"%PREV_HTML%",
			sprintf("%d.html", prev),
			"%PREV_TITLE%",
			ptitle,
			"%NEXT_SLIDE%",
			sprintf(".slide-%s", jpegs[next]),
			"%ORIG%",
			escaped,
			"%SLIDE%",
			sprintf(".slide-%s", escaped),
		};
		push(&map, "%CAPTION%");
		if (names || exif) cap = '<P class="center">';
		if (names) {
			cap .= stitle .
			    '&nbsp;&nbsp;&nbsp;' .
			    sprintf("(%d/%d)\n", i, length(jpegs) - 1);
		}
		undef(exdata);
		if (exif) {
			do_exif(&exdata, jpeg);
			if (names) cap .= "<br>";
			cap .= exdata;
		}
		if (names || exif) cap .= "</P>\n";
		push(&map, cap);

		push(&map, "%NAV%");
		date_nav = '';
		do_nav(&date_nav, jpeg, prev, next, 1);
		push(&map, date_nav);

		buf = String_map(map, template);
		Fprintf(file, "%s\n", buf);

		if (dates &&
		    defined(d2 = f2date(jpeg)) &&
		    (first || (d.sdate != d2.sdate))) {
			d = d2;
			unless (first) thumbs .= "</DIV>\n";
			buf = num2mon{d.mon};
			thumbs .= "<p><a name=\"${buf}_${d.day}\">";
			cap = "${buf} ${d.day} ${d.year}";
			thumbs .= cap . "</a>";
			cap = ".cap-${buf}-${d.day}-${d.year}";
			// .cap-January-09-2011, if exists, is appended
			if (exists(cap) && (cap = `cat ${cap}`)) {
				thumbs .= ': ' . cap;
			}
			thumbs .= "<br>\n<DIV class=\"center\">\n";
		}

		if (exif && exif_hover) stitle .= " " . exdata;
		thumbs .= sprintf(
		    '<a href="%s">' .
		    '<img src=".thumb-%s" alt="%s" title="%s" border="0"/>' . 
		    '</a>' . "\n",
		    file, escaped, stitle, stitle);
	    	first = 0;
	}
	
	/* do index.html */
	unless (f = fopen(indexf, "rv")) die("index.html");
	read(f, &template, -1);
	fclose(f);
	undef(map);
	push(&map, "%TITLE%");
	push(&map, title);
	push(&map, "%THUMBS%");
	thumbs .= "</DIV>\n";
	push(&map, thumbs);
	date_nav = '';
	push(&map, "%NAV%");
	do_nav(&date_nav, jpegs[1], undef, undef, 0);
	push(&map, date_nav);
	buf = String_map(map, template);
	if (exists(".index-include")) {
		buf .= `cat .index-include`;
	}
	Fprintf("index.html", "%s", buf);
	unless (f = fopen("~/.photos/photos.css", "rv")) die("photos.css");
	read(f, &buf, -1);
	fclose(f);
	Fprintf("photos.css", "%s", buf);
}

/*
 * XXX - what this needs is a hash and then at the end I push the info
 * I want in the order I want.
 */
int
do_exif(string &cap, string jpeg)
{
	FILE	f = popen("exiftags -a '${jpeg}'", "rv");
	string	save, buf, maker = '';
	string	v[];
	string	iso = undef;
	int	thumb = 0;
	int	i;
	string	tags{string};

	while (buf = <f>) {
		switch (trim(buf)) {
		    case /^Equipment Make: (.*)/:
			maker = $1;
			if (maker == "OLYMPUS IMAGING CORP.") {
				maker = "Olympus";
			}
			if (maker == "NIKON CORPORATION") {
				maker = "Nikon";
			}
			break;
		    case /^Camera Model: (.*)/:
			save = $1;
			if (save =~ /${maker}/i) {
				tags{"camera"} = save;
			} else {
				tags{"camera"} = "${maker} ${save}";
			}
			if (save == "TG-1") tags{"lens"} = "25-100mm f2.0";
			if (save =~ /Canon PowerShot S95/) {
				tags{"lens"} = "28-105 mm";
			}
			if (save =~ /Canon PowerShot S100/) {
				tags{"lens"} = "24-120mm";
			}
			break;
		    case /Lens Name: (.*)/:
			if ($1 =~ /EF\d/) $1 =~ s/EF/EF /;
			if ($1 =~ /EF-S\d/) $1 =~ s/EF-S/EF-S /;
			if ($1 =~ / USM/) $1 =~ s/ USM//;
			if ($1 == "30mm") $1 = "Sigma 30mm f/1.4";
			if ($1 == "90mm") $1 = "Tamron 90mm macro";
			if ($1 == "18-200mm") $1 = "Tamron 18-200mm";
			if ($1 == "18-250mm") $1 = "Tamron 18-250mm";
			if ($1 == "18-270mm") $1 = "Tamron 18-270mm";
			if ($1 == "170-500mm") $1 = "Sigma 170-500mm";
			$1 =~ s|f/|f|;
			tags{"lens"} = $1;
			break;
		    case /Lens Size: 10.00 - 22.00 mm/:
			tags{"lens"} = "EF-S 10-22mm f/3.5-4.5";
			break;
		    case /Exposure Bias: (.*)/:
			if ($1 != "0 EV") {
				unless ($1 =~ /^-/) $1 = "+" . $1;
				tags{"bias"} = $1;
			}
			break;
		    case /^Exposure Time: (.*)/:
			save = $1;
		    	$1 =~ /(\d+)\/(\d+) sec/;
			if ((int)$1 > 1) {
				i = (int)$2/(int)$1;
				save = "1/${i}";
			}
			tags{"time"} = save;
			break;
		    case /Lens Aperture: (.*)/:
		    case /F-Number: (.*)/:
			$1 =~ s|/||;
			tags{"fstop"} = $1;
			break;
		    case /ISO Speed Rating: (.*)/:
			iso = undef;
			if ($1 == "Auto") {
				iso = "ISO ${$1}";
			} else if ($1 == "Unknown") {
				;
			} else unless ((int)$1 == 0) {
				iso = "ISO ${$1}";
			}
			if (defined(iso)) tags{"iso"} = iso;
			break;
		    case /Focal Length .35mm Equiv.: (.*)/:
		    case /Focal Length: (.*)/:
			save = $1;
			if (tags{"camera"} =~ /Canon PowerShot S95/) {
				save =~ s/ mm//;
				save = (string)(int)((float)save * 4.7);
				save .= " mm";
			}
			if (tags{"camera"} =~ /Canon PowerShot S100/) {
				save =~ s/ mm//;
				save = (string)(int)((float)save * 4.61538);
				save .= " mm";
			}
			unless (defined(tags{"focal"})) {
				tags{"focal"} = save;
			}
			break;
		    case /Metering Mode: (.*)/:
			unless (defined(tags{"metering"})) {
				tags{"metering"} = "${$1} metering";
			}
			break;
		    case /White Balance: (.*)/:
			unless ($1 =~ /white balance/) $1 .= " white balance";
			$1 =~ s/white balance/WB/;
			unless (defined(tags{"balance"})) {
				tags{"balance"} = $1;
			}
			break;
		    case /Compression Scheme: JPEG Compression .Thumbnail./:
		    	thumb = 1;
			break;
		}
	}
	fclose(f);
	cap = "";
	if (defined(tags{"camera"})) push(&v, tags{"camera"});
	if (defined(tags{"lens"})) {
		if (defined(tags{"focal"}) && 
		    (tags{"lens"} =~ /[0-9]-[0-9]/)) {
		    	tags{"lens"} .= " @ " . tags{"focal"};
		}
		push(&v, tags{"lens"});
	}
	if (defined(tags{"fstop"})) push(&v, tags{"fstop"});
	if (defined(tags{"time"})) push(&v, tags{"time"});
	if (defined(tags{"bias"})) push(&v, tags{"bias"});
	if (defined(tags{"iso"})) push(&v, tags{"iso"});
	if (defined(tags{"metering"})) push(&v, tags{"metering"});
	if (defined(tags{"balance"})) push(&v, tags{"balance"});
	if (defined(v)) cap = join(", ", v);
	return (thumb);
}

int
rotation(string file)
{
	string	r = `exif -m -t Orientation '${file}'`;

	switch (r) {
	    case /right.*top/i:
		return (90);
	    case /left.*bottom/i:
		return (-90);
	    default:
		return (0);
	}
}

/*
 * This is called for both index nav and slide nav.
 * For index nav, unless nav is set, do nothing.
 * For slide nav, always do at least 
 * prev | index | next 
 * and optionally
 * prev | next | prev month | index | next month | prev year | next year
 */
void
do_nav(string &date_nav, string jpeg, int prev, int next, int slide)
{
	int	i, mon, did_it;
	string	buf, month;
	date	d;

	date_nav = '';
	if (!nav && !slide) return;

	unless (defined(d = f2date(jpeg))) return;
	month = num2mon{d.mon}[0..2];

	if (slide) {
		/* <<< prev | January | next >>> */
		date_nav .= '<a href="' . sprintf("%d.html", prev) .
		    '">&lt;&lt; prev pic</a>&nbsp;&nbsp;';
		date_nav .= "\n";
		unless (nav) {
			date_nav .= '<a href="index.html">Index</a>&nbsp;&nbsp;';
			date_nav .= "\n";
		}
		date_nav .= '<a href="' . sprintf("%d.html", next) .
		    '">next pic &gt;&gt;</a>';
		date_nav .= "\n";

		unless (nav) return;
	}

	/* <<< prev | next >>> |  <<< January >>> | <<< 2003 >>> */
	date_nav .= "\n";
	date_nav .= '&nbsp;&nbsp;&nbsp;&nbsp;';
	date_nav .= "\n";

	/* do the <<< for the prev month */
	for (i = 0; i < 12; i++) {
		mon = d.mon - i;
		if (mon == 1) {
			buf = sprintf("../../%d/%02d/index.html", d.year-1, 12);
		} else {
			buf = sprintf("../../%d/%02d/index.html", d.year,mon-1);
		}
		if (exists(buf)) break;
	}
	if (exists(buf)) date_nav .= '<a href="' . buf . '">&lt;&lt;&lt;</a>';
	date_nav .= "\n";

	/* do the link to index.html for this month */
	if (slide) {
		date_nav .= '&nbsp;&nbsp;<a href="index.html">' . 
		    month . " index" . '</a>&nbsp;&nbsp;';
	} else {
		date_nav .= "&nbsp;&nbsp;${month}&nbsp;&nbsp;";
	}
	date_nav .= "\n";

	/* do the >>> for next month */
	for (i = 0; i < 12; i++) {
		mon = d.mon + i;
		if (mon == 12) {
			buf = sprintf("../../%d/%02d/index.html", d.year+1, 1);
		} else {
			buf = sprintf("../../%d/%02d/index.html", d.year,mon+1);
		}
		if (exists(buf)) break;
	}
	if (exists(buf)) {
		date_nav .= '<a href="' . buf . '">&gt;&gt;&gt;</a>';
	}

	date_nav .= "\n";
	date_nav .= '&nbsp;&nbsp;&nbsp;&nbsp;';
	date_nav .= "\n";

	did_it = 0;
	buf = sprintf("../../%d/%02d/index.html", d.year - 1, d.mon);
	unless (exists(buf)) for (i = 1; i < 12; i++) {
		buf = sprintf("../../%d/%02d/index.html", d.year - 1, d.mon+i);
		if (exists(buf)) break;
		buf = sprintf("../../%d/%02d/index.html", d.year - 1, d.mon-i);
		if (exists(buf)) break;
	}
	if (exists(buf)) {
		date_nav .= '<a href="' .
		    buf . '">&lt;&lt;&lt;</a>&nbsp;' .  "${d.year}";
		date_nav .= "\n";
		did_it++;
	}
	buf = sprintf("../../%d/%02d/index.html", d.year + 1, d.mon);
	unless (exists(buf)) for (i = 1; i < 12; i++) {
		buf = sprintf("../../%d/%02d/index.html", d.year + 1, d.mon+i);
		if (exists(buf)) break;
		buf = sprintf("../../%d/%02d/index.html", d.year + 1, d.mon-i);
		if (exists(buf)) break;
	}
	if (exists(buf)) {
		unless (did_it) date_nav .= "${d.year}";
		date_nav .= '&nbsp;<a href="' . buf . '">&gt;&gt;&gt;</a>';
		date_nav .= "\n";
	}
}

void
dotfiles(void)
{
	string	file, buf;

	unless (isdir("~/.photos")) mkdir("~/.photos");
	file = "~/.photos/slide.html";
	unless (exists(file)) {
		buf = <<'END'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<HTML>
  <HEAD>
    <META http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
    <TITLE>%TITLE%</TITLE>
    <LINK rel="stylesheet" type="text/css" href="photos.css">
    <LINK rel="contents" href="index.html">
    <LINK rel="next" href="%NEXT_HTML%" title="%NEXT_TITLE%">
    <LINK rel="previous" href="%PREV_HTML%" title="%PREV_TITLE%">
    <SCRIPT type="text/javascript" language="javascript" defer>
       <!--
       if (document.images)    {
          Image1          = new Image();
          Image1.src      = "%NEXT_SLIDE%";
       }       //-->   
    </SCRIPT>
  </HEAD>

  <BODY>
    <P class="center">
      %NAV%
    </P>
    <DIV class="center">
      <TABLE bgcolor="#ffffff" cellspacing=0 cellpadding=4>
        <TR>
          <TD class="slide">
            <A href="%ORIG%">
	    <IMG src="%SLIDE%" alt="%TITLE%"
	    title="Click here to see full size, then use your back button."
	    border=0></a>
          </TD>
        </TR>
      </TABLE>
      <P>
      %CAPTION%
    </DIV>
  </BODY>
</HTML>
END;
		Fprintf(file, "%s", buf);
	}
	file = "~/.photos/index.html";
	unless (exists(file)) {
		buf = <<'END'
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">

<HTML>
  <HEAD>
    <META http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
    <TITLE>%TITLE%</TITLE>
    <LINK rel="stylesheet" type="text/css" href="photos.css">
  </HEAD>

  <BODY>
    %TITLE%
    &nbsp;
    &nbsp;
    &nbsp;
    &nbsp;
    %NAV%
    <p>
    %THUMBS%
    <p align="center">
    %NAV%
    <P class="small">
    For each picture there are 3 sizes:
    (1) the index thumbnails you are looking at,
    (2) a mid sized picture that you get to by clicking the thumbnail,
    (3) the original that you get to by clicking the midsize.
    Legal crud: everything is copyrighted by whoever took the picture.
    In the unlikely event you want to use a picture, please ask just to make
    us feel good.
    </P>
  </BODY>
</HTML>
END;
		Fprintf(file, "%s", buf);
	}
	file = "~/.photos/photos.css";
	unless (exists(file)) {
		buf = <<'END'
.center { 
  text-align: center;
}

.center table { 
  margin-left: auto;
  margin-right: auto;
  text-align: center;
}

body {
  font-family: verdana, sans-serif;
  background: #000000;
  color: #DDDDDD;
}

a:link {
  color: #95DDFF;
  background: transparent;
}

a:visited {
  color: #AAAAAA;
  background: transparent;
}

a:hover {
  color: #BBDDFF;
  background: #555555;
}

.small {
  font-size: 50%;
}

.large {
  font-size: 200%;
}

.tiled {
  background-image: url(".tile.png");
  background-repeat: repeat-x;
  background-color: #000000;
  padding: 0;
}

.thumb {
  background-color: #000000;
  text-align: center;
  vertical-align: middle;
}

.slide {
  background-color: #ffffff;
  text-align: center;
  vertical-align: middle;
}
END;
		Fprintf(file, "%s", buf);
	}
}
