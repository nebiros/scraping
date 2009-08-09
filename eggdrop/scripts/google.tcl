#
# Google Scraper
#
# Juan Felipe Alvarez Saldarriaga <jfalvarez at vesifront dot org>

# Max results.
set google_config(max) 5

# Deny channels
set google_config(deny_chans) {
}

# Version
set google_config(ver) 0.1

# Include packages.
package require http
package require ncgi

# Public command.
bind pub - !google pub_google

# Google function.
proc pub_google { nick uhost hand chan arg } {
	global google_config

	if { [lsearch [string tolower $google_config(deny_chans)] [string tolower $chan]] != "-1" } {
    	return 0
  	}

  	if { $arg == "" } {
    	putserv "NOTICE $nick :Usage: !google <search terms>"
	    return 0
  	}

	search $chan $nick $arg
}

# Search on google and display results.
proc search { chan nick search } {
	global google_config

	regsub -all " " $search "+" search

	# Set result type.
	set extra ""
	set type search

	if { [string match -nocase define:* $search] } {
		set extra &oi=glossary_definition
		set type dict
		regsub {[Dd]efine:} $search {define:} search
	}

	# Set google search url.
	set url http://www.google.com/search?q=$search&num=$google_config(max)$extra

	# Connect to google.
	http::config -useragent "Mozilla/5.0"
    set token [http::geturl $url]
    set data [http::data $token]
    http::cleanup $token

	# Create a temp file with the page html string.
    set tmp_file "/tmp/tmp_file_[expr int(rand()*32768)].[pid].xml"
    set fp [open $tmp_file "w"]
    puts -nonewline $fp $data
    close $fp

	# Parse the temp file with tity.
	set tidy_command "tidy -qm -w 0 -utf8 -asxml $tmp_file 2> /dev/null"
	catch { eval exec $tidy_command }

    set fp [open $tmp_file "r"]
    set tidy [read $fp]
    set tidy [split $tidy "\n"]
    catch { close $fp }

    # file delete -force -- $tmp_file

	switch $type {
		search {
			set results ""
			set links_counter 1

			foreach row $tidy {
				if { [regexp -nocase -- {Your search.*did not match any documents} $row] } {
					putserv "PRIVMSG $chan :No results"
					return 0
				}

				
				if { [regexp -nocase -- {<a.*href=.*class="l"} $row] } {
					regexp -nocase -- {.*<a href="(.*)" class="l">(.*)</a>.*} $row all link text
					set link [ncgi::decode $link]
					set text [striptags [ncgi::decode $text]]

            		set title [format "%u. %s" $links_counter $text]

					if { $links_counter == 1  } {
						set public_result "$title <$link>";
					}

					set results "$results $title <$link>;"

					incr links_counter
				}
			}

			putserv "PRIVMSG $chan :$nick: $public_result"

			if { $links_counter > 1 } {
				putserv "NOTICE $nick :$results"
			}
		}
		dict {
			set def_counter 1

			foreach row $tidy {
				if { [regexp -nocase -- {No definitions were found for.*} $row] } {
					putserv "PRIVMSG $chan :No definition"
					return 0
				}

				if { [regexp -nocase -- {<li>.*} $row] && $def_counter == 1 } {
					regexp -nocase -- {<li>(.*)<br />.*} $row all text
					incr def_counter
				}

				if { [regexp -nocase -- {<a href=\"/url\?&amp;q=.*} $row] && $def_counter == 2 } {
					regexp -nocase -- {<a href=\"/url\?&amp;q=(.*)(&amp;)ei=.*} $row all link
					set link [ncgi::decode $link]
					break
				}
			}

			putserv "PRIVMSG $chan :$nick: $text <$link>"
		}
	}
}

proc striptags str {
    regsub -all {<.*?>} $str {} str
    return $str
}


# Loaded.
putlog "google.tcl \[ OK \]"
putlog "Google Scraper $google_config(ver) - Loaded"
