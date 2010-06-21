/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2004-2010, University of Amsterdam
			      VU University Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(cp_server,
	  [ cp_server/0,
	    cp_server/1,		% +Options
	    cp_welcome/0
	  ]).

/** <module> ClioPatria main module

This module loads the ClioPatria  server   as  a  library, providing the
public predicates defined in the header.   Before loading this file, the
user should set up a the search path =cliopatria=. For example:

==
:- dynamic
	user:file_search_path/2.
:- multifile
	user:file_search_path/2.

user:file_search_path(cliopatria, '/usr/local/cliopatria').

:- use_module(cliopatria(load)).
==

*/

:- dynamic
	user:file_search_path/2.
:- multifile
	user:file_search_path/2.

:- (   user:file_search_path(cliopatria, _)
   ->  true
   ;   prolog_load_context(directory, Dir),
       assert(user:file_search_path(cliopatria, Dir))
   ).

:- load_files([version], [silent(true), if(not_loaded)]).
:- check_prolog_version(5111).		% Demand >= 5.11.1

:- load_files([ parms,
		page,			% HTML Page layout
		library(option),
		library(debug),
		library(lists),
		library(settings),
		library(error),
		library(broadcast),
		server,
		library(semweb/rdf_db),
		library(semweb/rdf_persistency),
		library(semweb/rdf_portray),
		library(http/http_session),
		library(http/http_dispatch),
		library(http/thread_httpd),
		user_db,			% User database
		openid,				% OpenID login management
		rdf_store,			% Setup RDF-store
		api(journal),			% export journal information
		http_browse			% Browse the repository
	      ],
	      [ silent(true),
		if(not_loaded)
	      ]).

%%	cp_server is det.
%%	cp_server(:Options) is det.
%
%	Start the HTTP server.  Defined options are:
%
%		* port(Port)
%		Attach to Port instead of the port specified in the
%		configuration file settings.db.
%
%		* after_load(:Goal)
%		Run Goal after loading/initialising the database, but
%		before releasing the server to the public.

:- meta_predicate
	cp_server(:).

cp_server :-
	cp_server([]).

cp_server(Options) :-
	meta_options(is_meta, Options, QOptions),
	load_settings('settings.db'),
	option(after_load(AfterLoad), QOptions, true),
	attach_account_info,
	set_session_options,
	setting(http:port, DefPort),
	setting(http:workers, Workers),
	setting(http:worker_options, Settings),
	merge_options([workers(Workers)|QOptions], Settings, HTTPOptions),
	option(port(Port), QOptions, DefPort),
	serql_server(Port, HTTPOptions),
	print_message(informational, serql(server_started(Port))),
	serql_server_set_property(loading(true)),
	rdf_setup_store(QOptions),
	call(AfterLoad),
	serql_server_set_property(loading(false)).

is_meta(after_load).

%%	attach_account_info
%
%	Set   the   registered   user-database     from    the   setting
%	cliopatria:user_data.

attach_account_info :-
	setting(cliopatria:user_data, File),
	set_user_database(File).

%%	set_session_options
%
%	Initialise session timeout from =|http:max_idle_time|=.

set_session_options :-
	setting(http:max_idle_time, Idle),
	http_set_session_options([timeout(Idle)]).


		 /*******************************
		 *	 UPDATE SETTINGS	*
		 *******************************/

update_workers(New) :-
	setting(http:port, Port),
	http_current_worker(Port, _),
	http_workers(Port, New).

:- listen(settings(changed(http:max_idle_time, _, New)),
	  http_set_session_options([timeout(New)])).
:- listen(settings(changed(http:workers, _, New)),
	  update_workers(New)).


		 /*******************************
		 *	      BANNER		*
		 *******************************/

%%	cp_welcome
%
%	Print welcome banner.

cp_welcome :-
	setting(http:port, Port),
	print_message(informational, serql(welcome(Port))).


		 /*******************************
		 *	     MESSAGES		*
		 *******************************/

:- multifile
	prolog:message/3.

prolog:message(serql(server_started(Port))) -->
	{ gethostname(Host),
	  http_location_by_id(cliopatria_home, Home)
	},
	[ 'Started ClioPatria server at port ~w'-[Port], nl,
	  'You may access the server at http://~w:~w~w'-[Host, Port, Home]
	].
prolog:message(serql(welcome(DefaultPort))) -->
	[ nl,
	  'Use one of the calls below to start the ClioPatria server:', nl, nl,
	  '  ?- cp_server.               % start at port ~w'-[DefaultPort], nl,
	  '  ?- cp_server([port(Port)]). % start at Port'
	].
