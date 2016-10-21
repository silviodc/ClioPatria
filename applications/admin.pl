/*  Part of ClioPatria SPARQL server

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2004-2010, University of Amsterdam,
			      VU University Amsterdam

    This program is free software; you can redistribute it and/o<r
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(
  cpa_admin,
  [
    allow//3,     % +Read, +Write, +Admin
    reply_login/2 % +Opts, +MTs
  ]
).

:- use_module(library(html/html_ext)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_session)).
:- use_module(library(http/html_write)).
:- use_module(library(http/html_head)).
:- use_module(library(http/mimetype)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(url)).
:- use_module(library(debug)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(http_settings)).

:- use_module(cp(components/basics)).
:- use_module(cp(skin/cliopatria)).
:- use_module(cp(user/user_db)).
:- use_module(cp(user/users)).

/** <module> ClioPatria administrative interface

This module provides HTTP services to perform administrative actions.

@tbd	Ideally, this module should be split into an api-part, a
	component-part and the actual pages.  This also implies that
	the current `action'-operations must (optionally) return
	machine-friendly results.
*/

:- http_handler(cliopatria('admin/form/createAdmin'),	   create_admin,	    []).
:- http_handler(cliopatria('admin/form/addUser'),	   add_user_form,	    []).
:- http_handler(cliopatria('admin/form/addOpenIDServer'),  add_openid_server_form,  []).
:- http_handler(cliopatria('admin/addUser'),		   add_user,		    []).
:- http_handler(cliopatria('admin/selfRegister'),	   self_register,	    []).
:- http_handler(cliopatria('admin/addOpenIDServer'),	   add_openid_server,	    []).
:- http_handler(cliopatria('admin/form/editUser'),	   edit_user_form,	    []).
:- http_handler(cliopatria('admin/editUser'),		   edit_user,		    []).
:- http_handler(cliopatria('admin/delUser'),		   del_user,		    []).
:- http_handler(cliopatria('admin/form/editOpenIDServer'), edit_openid_server_form, []).
:- http_handler(cliopatria('admin/editOpenIDServer'),	   edit_openid_server,	    []).
:- http_handler(cliopatria('admin/delOpenIDServer'),	   del_openid_server,	    []).
:- http_handler(cliopatria('admin/settings'),		   settings,		    []).
:- http_handler(cliopatria('admin/save_settings'),	   save_settings,	    []).


		 /*******************************
		 *	      ADD USERS		*
		 *******************************/

%%	create_admin(+Request)
%
%	Create the administrator login.

create_admin(_Request) :-
	(   current_user(_)
	->  throw(error(permission_error(create, user, admin),
			context(_, 'Already initialized')))
	;   true
	),
	reply_html_page(cliopatria(default),
			title('Create administrator'),
			[ h1(align(center), 'Create administrator'),

			  p('No accounts are available on this server. \c
			  This form allows for creation of an administrative \c
			  account that can subsequently be used to create \c
			  new users.'),

			  \new_user_form([ user(admin),
					   real_name('Administrator')
					 ])
			]).


%%	add_user_form(+Request)
%
%	Form to register a user.

add_user_form(_Request) :-
	authorized(admin(add_user)),
	reply_html_page(cliopatria(default),
			title('Add new user'),
			[ \new_user_form([])
			]).

new_user_form(Options) -->
	{ (   option(user(User), Options)
	  ->  UserOptions = [value(User)],
	      PermUser = User
	  ;   UserOptions = [],
	      PermUser = (-)
	  )
	},
	html([ h1('Add new user'),
	       form([ action(location_by_id(add_user)),
		      method('POST')
		    ],
		    table([ class((form))
			  ],
			  [ \realname(Options),
			    \input(user,     'Login',
				   UserOptions),
			    \input(pwd1,     'Password',
				   [type(password)]),
			    \input(pwd2,     'Retype',
				   [type(password)]),
			    \permissions(PermUser),
			    tr(class(buttons),
			       td([ colspan(2),
				    align(right)
				  ],
				  input([ type(submit),
					  value('Create')
					])))
			  ]))
	     ]).


input(Name, Label, Options) -->
	html(tr([ th(align(right), Label),
		  td(input([name(Name),size(40)|Options]))
		])).

%	Only provide a realname field if this is not already given. This
%	is because firefox determines the login user from the text field
%	immediately above the password entry. Other   browsers may do it
%	different, so only having one text-field  is probably the savest
%	solution.

realname(Options) -->
	{ option(real_name(RealName), Options) }, !,
	hidden(realname, RealName).
realname(_Options) -->
	input(realname, 'Realname', []).


%%	add_user(+Request)
%
%	API  to  register  a  new  user.  The  current  user  must  have
%	administrative rights or the user-database must be empty.

add_user(Request) :-
	(   \+ current_user(_)
	->  FirstUser = true
	;   authorized(admin(add_user))
	),
	http_parameters(Request,
			[ user(User),
			  realname(RealName),
			  pwd1(Password),
			  pwd2(Retype),
			  read(Read),
			  write(Write),
			  admin(Admin)
			],
			[ attribute_declarations(attribute_decl)
			]),
	(   current_user(User)
	->  throw(error(permission_error(create, user, User),
			context(_, 'Already present')))
	;   true
	),
	(   Password == Retype
	->  true
	;   throw(password_mismatch)
	),
	password_hash(Password, Hash),
	phrase(allow(Read, Write, Admin), Allow),
	user_add(User,
		 [ realname(RealName),
		   password(Hash),
		   allow(Allow)
		 ]),
	(   FirstUser == true
	->  user_add(anonymous,
		     [ realname('Define rights for not-logged in users'),
		       allow([read(_,_)])
		     ]),
	    reply_login([user(User), password(Password)], [text/html])
	;   users_handler(Request)
	).

%%	self_register(Request)
%
%	Self-register and login a new user if
%	cliopatria:enable_self_register is set to true.
%       Users are registered with full read
%	and limited (annotate-only) write access.
%
%	Returns a HTTP 403 forbidden error if:
%	- cliopatria:enable_self_register is set to false
%	- the user already exists

self_register(Request) :-
	http_location_by_id(self_register, MyUrl),
	(   \+ setting(cliopatria:enable_self_register, true)
	->  throw(http_reply(forbidden(MyUrl)))
	;   true
	),
	http_parameters(Request,
			[ user(User),
			  realname(RealName),
			  password(Password)
			],
			[ attribute_declarations(attribute_decl)
			]),
	(   current_user(User)
	->  throw(http_reply(forbidden(MyUrl)))
	;   true
	),
	password_hash(Password, Hash),
	Allow = [ read(_,_), write(_,annotate) ],
	user_add(User, [realname(RealName), password(Hash), allow(Allow)]),
	reply_login([user(User), password(Password)], [text/html]).


%%	edit_user_form(+Request)
%
%	Form to edit user properties

edit_user_form(Request) :-
	authorized(admin(user(edit))),
	http_parameters(Request,
			[ user(User)
			],
			[ attribute_declarations(attribute_decl)
			]),

	reply_html_page(cliopatria(default),
			title('Edit user'),
			\edit_user_form(User)).

%%	edit_user_form(+User)//
%
%	HTML component to edit the properties of User.

edit_user_form(User) -->
	{ user_property(User, realname(RealName))
	},
	html([ h1(['Edit user ', User, ' (', RealName, ')']),

	       form([ action(location_by_id(edit_user)),
		      method('POST')
		    ],
		    [ \hidden(user, User),
		      table([ class((form))
			    ],
			    [ \user_property(User, realname, 'Real name', []),
			      \permissions(User),
			      tr(class(buttons),
				 td([ colspan(2),
				      align(right)
				    ],
				    input([ type(submit),
					    value('Modify')
					  ])))
			    ])
		    ]),

	       p(\action(location_by_id(del_user)+'?user='+encode(User),
			 [ 'Delete user ', b(User), ' (', i(RealName), ')' ]))
	     ]).

user_property(User, Name, Label, Options) -->
	{  Term =.. [Name, Value],
	   user_property(User, Term)
	-> O2 = [value(Value)|Options]
	;  O2 = Options
	},
	html(tr([ th(class(p_name), Label),
		  td(input([name(Name),size(40)|O2]))
		])).

permissions(User) -->
	html(tr([ th(class(p_name), 'Permissions'),
		  td([ \permission_checkbox(User, read,  'Read'),
		       \permission_checkbox(User, write, 'Write'),
		       \permission_checkbox(User, admin, 'Admin')
		     ])
		])).

permission_checkbox(User, Name, Label) -->
	{ (   User \== (-),
	      (	  user_property(User, allow(Actions))
	      ->  true
	      ;	  openid_server_property(User, allow(Actions))
	      ),
	      pterm(Name, Action),
	      memberchk(Action, Actions)
	  ->  Opts = [checked]
	  ;   def_user_permissions(User, DefPermissions),
	      memberchk(Name, DefPermissions)
	  ->  Opts = [checked]
	  ;   Opts = []
	  )
	},
	html([ input([ type(checkbox),
		       name(Name)
		     | Opts
		     ]),
	       Label
	     ]).

def_user_permissions(-, [read]).
def_user_permissions(admin, [read, write, admin]).


%%	edit_user(Request)
%
%	Handle reply from edit user form.

edit_user(Request) :-
	authorized(admin(user(edit))),
	http_parameters(Request,
			[ user(User),
			  realname(RealName,
				   [ optional(true),
				     length > 2,
				     description('Comment on user identifier-name')
				   ]),
			  read(Read),
			  write(Write),
			  admin(Admin)
			],
			[ attribute_declarations(attribute_decl)
			]),
	modify_user(User, realname(RealName)),
	modify_permissions(User, Read, Write, Admin),
	users_handler(Request).


modify_user(User, Property) :-
	Property =.. [_Name|Value],
	(   (   var(Value)
	    ;	Value == ''
	    )
	->  true
	;   set_user_property(User, Property)
	).

modify_permissions(User, Read, Write, Admin) :-
	phrase(allow(Read, Write, Admin), Allow),
	set_user_property(User, allow(Allow)).

allow(Read, Write, Admin) -->
	allow(read, Read),
	allow(write, Write),
	allow(admin, Admin).

allow(Access, on) -->
	{ pterm(Access, Allow)
	}, !,
	[ Allow
	].
allow(_Access, off) --> !,
	[].

pterm(read,  read(_Repositiory, _Action)).
pterm(write, write(_Repositiory, _Action)).
pterm(admin, admin(_Action)).


%%	del_user(+Request)
%
%	Delete a user

del_user(Request) :- !,
	authorized(admin(del_user)),
	http_parameters(Request,
			[ user(User)
			],
			[ attribute_declarations(attribute_decl)
			]),
	(   User == admin
	->  throw(error(permission_error(delete, user, User), _))
	;   true
	),
	user_del(User),
	users_handler(Request).


		 /*******************************
		 *	       LOGIN		*
		 *******************************/

reply_login(Opts, MTs) :-
  member(MT, MTs),
  reply_login_(Opts, MT), !.

reply_login_(Options, text/html) :-
	option(user(User), Options),
	option(password(Password), Options),
	validate_password(User, Password), !,
	login(User),
	(   option(return_to(ReturnTo), Options)
	->  throw(http_reply(moved_temporary(ReturnTo)))
	;   reply_html_page(cliopatria(default),
			    \cp_title(["Login OK"]),
			    h1(align(center), ["Welcome ",\quote(User),"!"]))
	).
reply_login_(_, text/html) :-
	reply_html_page(cliopatria(default),
			title('Login failed'),
			[ h1('Login failed'),
			  p(['Password incorrect'])
			]).

%%	attribute_decl(+Param, -DeclObtions) is semidet.
%
%	Provide   reusable   parameter   declarations   for   calls   to
%	http_parameters/3.

attribute_decl(user,
	       [ description('User identifier-name'),
		 length > 1
	       ]).
attribute_decl(realname,
	       [ description('Comment on user identifier-name')
	       ]).
attribute_decl(description,
	       [ optional(true),
		 description('Descriptive text')
	       ]).
attribute_decl(password,
	       [ description('Password')
	       ]).
attribute_decl(pwd1,
	       [ length > 5,
		 description('Password')
	       ]).
attribute_decl(pwd2,
	       [ length > 5,
		 description('Re-typed password')
	       ]).
attribute_decl(openid_server,
	       [ description('URL of an OpenID server')
	       ]).
attribute_decl(read,
	       [ description('Provide read-only access to the RDF store')
	       | Options])   :- bool(off, Options).
attribute_decl(write,
	       [ description('Provide write access to the RDF store')
	       | Options])   :- bool(off, Options).
attribute_decl(admin,
	       [ description('Provide administrative rights')
	       | Options])   :- bool(off, Options).

bool(Def,
     [ default(Def),
       oneof([on, off])
     ]).


		 /*******************************
		 *	    OPENID ADMIN	*
		 *******************************/

%%	add_openid_server_form(+Request)
%
%	Return an HTML page to add a new OpenID server.

add_openid_server_form(_Request) :-
	authorized(admin(add_openid_server)),
	reply_html_page(cliopatria(default),
			title('Add OpenID server'),
			[ \new_openid_form
			]).


%%	new_openid_form// is det.
%
%	Present form to add a new OpenID provider.

new_openid_form -->
	html([ h1('Add new OpenID server'),
	       form([ action(location_by_id(add_openid_server)),
		      method('GET')
		    ],
		    table([ id('add-openid-server'),
			    class(form)
			  ],
			  [ \input(openid_server, 'Server homepage', []),
			    \input(openid_description, 'Server description',
				   []),
			    \permissions(-),
			    tr(class(buttons),
			       td([ colspan(2),
				    align(right)
				  ],
				  input([ type(submit),
					  value('Create')
					])))
			  ])),
	       p([ 'Use this form to define access rights for users of an ',
		   a(href('http://www.openid.net'), 'OpenID'), ' server. ',
		   'The special server ', code(*), ' specifies access for all OpenID servers. ',
		   'Here are some examples of servers:'
		 ]),
	       ul([ li(code('http://myopenid.com'))
		  ])
	     ]).


%%	add_openid_server(+Request)
%
%	Allow access from an OpenID server

add_openid_server(Request) :-
	authorized(admin(add_openid_server)),
	http_parameters(Request,
			[ openid_server(Server0,
					[ description('URL of the server to allow')]),
			  openid_description(Description,
					     [ optional(true),
					       description('Description of the server')
					     ]),
			  read(Read),
			  write(Write)
			],
			[ attribute_declarations(attribute_decl)
			]),
	phrase(allow(Read, Write, off), Allow),
	canonical_url(Server0, Server),
	Options = [ description(Description),
		    allow(Allow)
		  ],
	remove_optional(Options, Properties),
	openid_add_server(Server, Properties),
	users_handler(Request).

remove_optional([], []).
remove_optional([H|T0], [H|T]) :-
	arg(1, H, A),
	nonvar(A), !,
	remove_optional(T0, T).
remove_optional([_|T0], T) :-
	remove_optional(T0, T).


canonical_url(Var, Var) :-
	var(Var), !.
canonical_url(*, *) :- !.
canonical_url(URL0, URL) :-
	parse_url(URL0, Parts),
	parse_url(URL, Parts).


%%	edit_openid_server_form(+Request)
%
%	Form to edit user properties

edit_openid_server_form(Request) :-
	authorized(admin(openid(edit))),
	http_parameters(Request,
			[ openid_server(Server)
			],
			[ attribute_declarations(attribute_decl)
			]),

	reply_html_page(cliopatria(default),
			title('Edit OpenID server'),
			\edit_openid_server_form(Server)).

edit_openid_server_form(Server) -->
	html([ h1(['Edit OpenID server ', Server]),

	       form([ action(location_by_id(edit_openid_server)),
		      method('GET')
		    ],
		    [ \hidden(openid_server, Server),
		      table([ class(form)
			    ],
			    [ \openid_property(Server, description, 'Description', []),
			      \permissions(Server),
			      tr(class(buttons),
				 td([ colspan(2),
				      align(right)
				    ],
				    input([ type(submit),
					    value('Modify')
					  ])))
			    ])
		    ]),

	       p(\action(location_by_id(del_openid_server) +
			 '?openid_server=' + encode(Server),
			 [ 'Delete ', b(Server) ]))
	     ]).


openid_property(Server, Name, Label, Options) -->
	{  Term =.. [Name, Value],
	   openid_server_property(Server, Term)
	-> O2 = [value(Value)|Options]
	;  O2 = Options
	},
	html(tr([ th(align(right), Label),
		  td(input([name(Name),size(40)|O2]))
		])).


%%	openid_server_table(+Options)//
%
%	List registered openid servers

openid_server_table(Options) -->
	{ setof(S, openid_current_server(S), Servers), !
	},
	cp_table(
	  \cp_table_header(["Server","Description"]),
	  \openid_list_servers(Servers, Options)
	).
openid_server_table(_) -->
	[].

openid_list_servers([], _) -->
	[].
openid_list_servers([H|T], Options) -->
	openid_list_server(H, Options),
	openid_list_servers(T, Options).

openid_list_server(Server, Options) -->
	html(tr([td(\openid_server(Server)),
		 td(\openid_field(Server, description)),
		 \edit_openid_button(Server, Options)
		])).

edit_openid_button(Server, Options) -->
	{ option(edit(true), Options) }, !,
	html(td(a(href(location_by_id(edit_openid_server_form) +
		       '?openid_server='+encode(Server)
		      ), 'Edit'))).
edit_openid_button(_, _) --> [].



openid_server(*) --> !,
	html(*).
openid_server(Server) -->
	html(a(href(Server), Server)).

openid_field(Server, Field) -->
	{ Term =.. [Field, Value],
	  openid_server_property(Server, Term)
	}, !,
	html(Value).
openid_field(_, _) -->
	[].


%%	edit_openid_server(Request)
%
%	Handle reply from OpenID server form.

edit_openid_server(Request) :-
	authorized(admin(openid(edit))),
	http_parameters(Request,
			[ openid_server(Server),
			  description(Description),
			  read(Read),
			  write(Write),
			  admin(Admin)
			],
			[ attribute_declarations(attribute_decl)
			]),
	modify_openid(Server, description(Description)),
	openid_modify_permissions(Server, Read, Write, Admin),
	users_handler(Request).


modify_openid(User, Property) :-
	Property =.. [_Name|Value],
	(   (   var(Value)
	    ;	Value == ''
	    )
	->  true
	;   openid_set_property(User, Property)
	).


openid_modify_permissions(Server, Read, Write, Admin) :-
	phrase(allow(Read, Write, Admin), Allow),
	openid_set_property(Server, allow(Allow)).


%%	del_openid_server(+Request)
%
%	Delete an OpenID Server

del_openid_server(Request) :- !,
	authorized(admin(openid(delete))),
	http_parameters(Request,
			[ openid_server(Server)
			],
			[ attribute_declarations(attribute_decl)
			]),
	openid_del_server(Server),
	users_handler(Request).


		 /*******************************
		 *	       SETTINGS		*
		 *******************************/

%%	settings(+Request)
%
%	Show current settings. If user  has administrative rights, allow
%	editing the settings.

settings(_Request) :-
	(   catch(authorized(admin(edit_settings)), _, fail)
	->  Edit = true
	;   authorized(read(admin, settings)),
	    Edit = false
	),
	reply_html_page(cliopatria(default),
			title('Settings'),
			[ h1('Application settings'),
			  \http_show_settings([ edit(Edit),
						hide_module(false),
						action('save_settings')
					      ]),
			  \warn_no_edit(Edit)
			]).

warn_no_edit(true) --> !.
warn_no_edit(_) -->
	html(p(id(settings_no_edit),
	       [ a(href(location_by_id(login_form)), 'Login'),
		 ' as ', code(admin), ' to edit the settings.' ])).

%%	save_settings(+Request)
%
%	Save modified settings.

save_settings(Request) :-
	authorized(admin(edit_settings)),
	reply_html_page(cliopatria(default),
			title('Save settings'),
			\http_apply_settings(Request, [save(true)])).


		 /*******************************
		 *		EMIT		*
		 *******************************/

action(URL, Label) -->
	html([a([href(URL)], Label), br([])]).
