"Make sure this file is only sourced once
if exists("JavaAspectSourced")
	finish
endif
let JavaAspectSourced = "true"

" This module generates decorator source file for a given interface or class
" file based on a method implementation template.
"
" The following substitution keywords are used to replace the token with the
" actual text in the template.
"
" # follows a digit represents which method word to use, 
" for example, #1 denotes the second word in the method head.
"
" @ follows a digit represents which argument to use.
" for example, @0 denotes the first word in the argument list.
"
" @@ represents the whole argument list
"
" $ follows a digit represents which exception to use.
" for example, $0 denotes the first exception in the throw clause.
"
" $$ represents the whole exceptions list
"
" #return represents to add the return line even for void method.

" The following is an example of how to setup the template
"
" Method Signature:
"
" public int doSomething(int arg, String str)
" 		throws IOExeception;
"
" Template:
"
" try
" {
" 		#1 temp = delegate.#2(@@);
" }
" catch($0 e)
" {
" 		e.printStackTrace();
" }
"
" #1 is for int
" #2 is for doSomething
" @@ is for the whole parameter list (arg, str)
" $0 is for IOExeception
"
" Output:
"
" try
" {
" 		int temp = delegate.doSomething(arg, str);
" }
" catch (IOExeception e)
" {
" 		e.printStackTrace();
" }
"
" Module Instruction:
" We have to setup the template code first, and then highlight them.
"
" Next, there are three ways to decorate the template
"
" 1) Use java source as the input, which typically is an interface declaration.
" On command line :'<,'>CreateAspect
"
" 2) Use the java class as the input, pass the fully qualified java class name.
" For example :'<,'>CreateAspect "java.net.Socket"
" The generated decorator will be appended at the end of the current file.
"
" 3) Update the current decorator with the highlighted new template
" On command line :'<,'>UpdateAspect
" We can take off the @Override token if we don't want to update a particular
" method.
"
command! -range -nargs=0 UpdateAspect :<line1>,<line2>call <SID>CreateAspect('')

command! -range -nargs=? CreateAspect :<line1>,<line2>call <SID>CreateAspect(<args>)

" The entry point of this module.
function! s:CreateAspect(...) range
	" Save the position so that we can get back to the same line.
	let position = line('.')
	let s:Template = join(getline(a:firstline, a:lastline), '')

	if (a:0 == 0)
		let first = search('^\s*public', 'n')
		silent exe first . ',$ call <SID>DecorateSource(0)'
	elseif (a:0 > 0 && strlen(a:1) == 0)
		let first = search('@Override', 'n')
		if (first == 0)
			let first = 1
		endif

		silent g/@Override/,/^\t{/,/^\t}/d
		silent exe first . ',$ call <SID>DecorateSource(1)'
	elseif (a:0 > 0 && strlen(a:1) > 0)
		silent call s:Javap(a:1)
	endif

	" Get back the starting point.
	exe position
endfunction

" Do the real work of decorating the template.
function! s:DecorateSource(hasOverride) range

	let current = a:firstline
	let output = []

	while (current <= a:lastline)
		let line = getline(current)
		let previousMatch = 0

		if (a:hasOverride && line =~# '^\s\+@Override')
			let current = current + 1
			let line = getline(current)
			let previousMatch = 1
		endif

		let hasPublic = (line =~# '^\s\+public')
		if (hasPublic && !a:hasOverride) || 
		\  (hasPublic && a:hasOverride && previousMatch)
			let previousMatch = 0

			let partition = split(line, '(\s*')
			let methodWords = s:GetMethodWords(partition[0])
			let parts = split(partition[1], ')')
			if (len(parts) > 0 && match(parts[0], ';') < 0)
				let arguments = s:GetArguments(parts[0])
			else
				let arguments = []
			endif

			call insert(output, split(line, 'public')[0] . '@Override')

			if (a:hasOverride == 0 && len(methodWords) == 4 && methodWords[1] != 'void')
				call insert(output, split(line, 'public')[0] . '@SuppressWarning("unchecked")', '')
			endif

			call insert(output, substitute(line, ';', '', ''))

			" This is more like a hack to parse throws clause in diffirent situations.
			let next = getline(current + 1)
			if (next =~# '^\s\+throws')
				let next = substitute(next, ';', '', '')
				let exceptions = split(split(next, 'throws\s\+')[1], ',\s\+')
				let current = current + 1
				call insert(output, next)
			elseif (len(parts) > 1 && parts[1] =~# '\s\+throws')
				let temp = substitute(parts[1], ';', '', '')
				let exceptions = split(split(temp, 'throws\s\+')[1], ',\s\+')
			elseif (len(parts) > 0 && parts[0] =~# '\s\+throws')
				let temp = substitute(parts[0], ';', '', '')
				let exceptions = split(split(temp, 'throws\s\+')[1], ',\s\+')
			endif

			" do the replacement
			let i = 0
			let template = s:Template
			while (i < strlen(s:Template))
				" process methodWords #
				if (s:Template[i] == '#')
					let next = i + 1
					let temp = ""

					while (next < strlen(s:Template))
						if (s:Template[next] =~# '\d')
							let temp = temp . s:Template[next]
							let i = next
						else
							break
						endif
						let next = next + 1
					endwhile

					if (strlen(temp) > 0)
						let template = substitute(template, '#'.temp, methodWords[str2nr(temp)], '')
					endif
				endif

				" process arguments @
				if (s:Template[i] == '@')
					let next = i + 1
					let temp = ""

					if (s:Template[next] == '@')
						let i = next
						let template = substitute(template, '@@', s:Concate(arguments), '')
					else
						while (next < strlen(s:Template))
							if (s:Template[next] =~# '\d')
								let temp = temp . s:Template[next]
								let i = next
							else
								break
							endif
							let next = next + 1
						endwhile

						if (strlen(temp) > 0)
							let template = substitute(template, '@'.temp, arguments[str2nr(temp)], '')
						endif
					endif
				endif

				" process exceptions $
				if (s:Template[i] == '$' && exists("exceptions"))
					let next = i + 1
					let temp = ""

					if (s:Template[next] == '$')
						let i = next
						let template = substitute(template, '\$\$', join(exceptions, ', '), '')
					else
						while (next < strlen(s:Template))
							if (s:Template[next] =~# '\d')
								let temp = temp . s:Template[next]
								let i = next
							else
								break
							endif
							let next = next + 1
						endwhile

						if (strlen(temp) > 0)
							let template = substitute(template, '\$'.temp, exceptions[str2nr(temp)], '')
						endif
					endif
				endif

				let i = i + 1
			endwhile

			let output = s:Filter(template, methodWords, exists("exceptions")) + output
			if (exists("exceptions"))
				unlet exceptions
			endif

		else
			call insert(output, line)
		endif

		let current = current + 1
	endwhile


	" delete the old lines
	exe a:firstline . ',' a:lastline . 'd'
	" append the replacement
	call append(a:firstline - 1, reverse(output))

endfunction

" Requirement: The current vim buffer should be empty, e.g. have no data.
function! s:Javap(className)

	exe "normal! G"
	if (strlen(getline('.')) > 0)
		exe "normal! o"
	endif
	let first = line('.')
	exe "read !javap " . a:className

	" Delete all the non-public lines.
	exe first . ',' . '$v/public/d'

	" Drop the package names.
	exe first . ',' . '$s/\%(\w\+\.\)\+\(\w\+\)/\1/g'

	" Delete all the constructors.
	exe first . ',' . '$g/public \w\+(/d'

	" Delete all the static methods.
	exe first . ',' . '$g/public static/d'

	" Delete all the final methods.
	exe first . ',' . '$g/public\( \w\+\)\= final/d'

	" Drop 'synchronized' keyword.
	exe first . ',' . '$s/synchronized//g'

	" Make the arguments valid.
	exe first . ',' . '$s/\(\w\+\)\([,)]\)/\=submatch(1). " " . tolower(submatch(1)) .  col(".").submatch(2)/g'

	" Break the throws clause into a new line.
	" exe first . ',' . '$s/\s\+throws/throws/'

	" The first line is class declaration, so skip it.
	exe first . ',' . '$call <SID>DecorateSource(0)'
endfunction

function! s:Concate(args)
	let retVal = ""
	let i = 0
	while (i < len(a:args))
		if (i % 2)
			if (i > 1)
				let retVal = retVal . ', '
			endif
			let retVal = retVal . a:args[i]
		endif

		let i = i + 1
	endwhile

	return retVal
endfunction

function! s:GetArguments(part)
	let arguments = split(substitute(a:part, ');\=\s*', '', ''), ',\=\s\+')
	let index = len(arguments) - 1

	while (index >= 0)
		let item = arguments[index]
		if (item =~# '\.\.\.')
			let arguments[index] = substitute(arguments[index], '\.', '', 'g')
			if ((index+1) / 2)
				let arguments[index-1] = arguments[index-1].'[]'
			else
				let arguments[index] = arguments[index].'[]'
			endif
		endif
		let index = index - 1
	endwhile

	return arguments
endfunction

function! s:GetMethodWords(part)
	let methodWords = split(a:part, '\s\+')
	let index = len(methodWords) - 1
	let generic = ''
	while (index >= 0)
		let item = methodWords[index]
		if (item =~ '^<')
			call remove(methodWords, index)
			let generic = item
		endif
		let index = index - 1
	endwhile

	if (strlen(generic))
		let methodWords = add(methodWords, generic)
	endif

	return methodWords
endfunction

function! s:Filter(intermediate, methodWords, exceptions)
	" The delegate method doesn't throw exceptions
	let source = a:intermediate
	if (a:exceptions == 0)
		let source = substitute(source, 'try\_[ \t]\{-}{', '', '')
		let partition = split(source, '}\_[ \t]*catch.\{-}{')
		" assuming there's no nested catch statement
		if (len(partition) > 1)
			let source = partition[0] . s:Trancate(partition[1])
		endif
	endif

	" We use append later which doesn't take  as a new line.
	let temp = reverse(split(source, ''))
	let output = []

	" void type doesn't return values
	if (a:methodWords[1] == 'void')
		let i = 0
		while (i < len(temp))
			if (temp[i] =~ '^\s\+void')
				let output = add(output, substitute(temp[i], 'void.\{-}=\s\+', '', ''))
			elseif (temp[i] =~ '#return\s\+\w\+')
				let output = add(output, substitute(temp[i], '#return.*', 'return;', ''))
			elseif (temp[i] =~ 'return\s\+\w\+')
				" don't copy the return line
			else
				let output= add(output, temp[i])
			endif

			let i = i + 1
		endwhile
	else
		let i = 0
		while (i < len(temp))
			if (temp[i] =~ '#return\s\+\w\+')
				let output = add(output, substitute(temp[i], '#', '', ''))
			else
				let output= add(output, temp[i])
			endif
			let i = i + 1
		endwhile
	endif

	if (len(a:methodWords) == 4)
		let temp = output
		let output = []
		let i = 0
		while (i < len(temp))
			if (temp[i] =~ '^\s\+'.a:methodWords[1])
				let rep = substitute(temp[i], '\s*=\s*', '&('.a:methodWords[1].')', '')
				let output = add(output, rep)
			else
				let output = add(output, temp[i])
			endif

			let i = i + 1
		endwhile
	endif

	return output

endfunction

function! s:Trancate(input)
	let i = 0
	let braces = []
	while (i < len(a:input))
		if (a:input[i] == '}')
			if (len(braces) == 0)
				let i = i + 1
				break
			else
				remove(braces, -1)
			endif
		elseif (a:input[i] == '{')
			let braces = add(braces, '{')
		endif

		let i = i + 1
	endwhile

	return strpart(a:input, i)
endfunction
