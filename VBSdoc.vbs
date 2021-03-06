'! Script for automatic generation of API documentation from special
'! comments in VBScripts.
'!
'! Portuguese localization contributed by Luis Da Costa <luisdc@libretrend.com>.
'!
'! @author  Ansgar Wiechers <ansgar.wiechers@planetcobalt.net>
'! @date    2020-06-28
'! @version 2.6.1

' This program is free software; you can redistribute it and/or
' modify it under the terms of the GNU General Public License
' as published by the Free Software Foundation; either version 2
' of the License, or (at your option) any later version.
'
' This program is distributed in the hope that it will be useful,
' but WITHOUT ANY WARRANTY; without even the implied warranty of
' MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
' GNU General Public License for more details.
'
' You should have received a copy of the GNU General Public License
' along with this program; if not, write to the Free Software
' Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

Option Explicit

' Some symbolic constants for internal use.
Private Const ForReading  = 1
Private Const ForWriting  = 2
Private Const WshRunning  = 0
Private Const WshFinished = 1

Private Const vbReplaceAll = -1

Private Const IndexFileName  = "index.html"
Private Const StylesheetName = "vbsdoc.css"
Private Const TextFont       = "Verdana, Arial, helvetica, sans-serif"
Private Const CodeFont       = "Lucida Console, Courier New, Courier, monospace"
Private Const BaseFontSize   = "14px"
Private Const CopyrightInfo  = "Created with <a href=""http://www.planetcobalt.net/sdb/vbsdoc.shtml"" target=""_blank"">VBSdoc</a>. &copy;2010 <a href=""mailto:ansgar.wiechers@planetcobalt.net"">Ansgar Wiechers</a>."

Private Const DefaultExtension = "vbs"
Private Const DefaultLanguage  = "en"

' Initialize global objects.
Private fso : Set fso = CreateObject("Scripting.FileSystemObject")
Private sh  : Set sh = CreateObject("WScript.Shell")
Private clog : Set clog = New CLogger

'! Match line-continuations.
Private reLineCont : Set reLineCont = CompileRegExp("[ \t]+_\n[ \t]*", True, True)
'! Match End-of-Line doc comments.
Private reEOLComment : Set reEOLComment = CompileRegExp("(^|\n)([ \t]*[^' \t\n].*)('![ \t]*.*(\n[ \t]*'!.*)*)", True, True)
'! Match @todo-tagged doc comments.
Private reTodo : Set reTodo = CompileRegExp("'![ \t]*@todo[ \t]*(.*\n([ \t]*'!([ \t]*[^@\s].*|\s*)\n)*)", True, True)
'! Match class implementations and prepended doc comments.
Private reClass : Set reClass = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*Class[ \t]+(\w+)([\s\S]*?)End[ \t]+Class", True, True)
'! Match constructor implementations and prepended doc comments.
Private reCtor : Set reCtor = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*((Public|Private)[ \t]+)?Sub[ \t]+(Class_Initialize)[ \t]*(\(\))?[\s\S]*?End[ \t]+Sub", True, True)
'! Match destructor implementations and prepended doc comments.
Private reDtor : Set reDtor = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*((Public|Private)[ \t]+)?Sub[ \t]+(Class_Terminate)[ \t]*(\(\))?[\s\S]*?End[ \t]+Sub", True, True)
'! Match implementations of methods/procedures as well as prepended
'! doc comments.
Private reMethod : Set reMethod = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*((Public([ \t]+Default)?|Private)[ \t]+)?(Function|Sub)[ \t]+(\w+)[ \t]*(\([\w\t ,]*\))?[\s\S]*?End[ \t]+\7", True, True)
'! Match property implementations and prepended doc comments.
Private reProperty : Set reProperty = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*((Public([ \t]+Default)?|Private)[ \t]+)?Property[ \t]+(Get|Let|Set)[ \t]+(\w+)[ \t]*(\([\w\t ,]*\))?[\s\S]*?End[ \t]+Property", True, True)
'! Match definitions of constants and prepended doc comments.
Private reConst : Set reConst = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*((Public|Private)[ \t]+)?Const[ \t]+(\w+)[ \t]*=[ \t]*(.*)", True, True)
'! Match variable declarations and prepended doc comments. Allow for combined
'! declaration:definition as well as multiple declarations of variables on
'! one line, e.g.:
'!   - Dim foo : foo = 42
'!   - Dim foo, bar, baz
Private reVar : Set reVar = CompileRegExp("(^|\n)(([ \t]*'!.*\n)*)[ \t]*(Public|Private|Dim|ReDim)[ \t]+(((\w+)([ \t]*\(\))?)[ \t]*(:[ \t]*(Set[ \t]+)?\7[ \t]*=.*|(,[ \t]*\w+[ \t]*(\(\))?)*))", True, True)
'! Match doc comments. This regular expression is used to process file-global
'! doc comments after all other elements in a given file were processed.
Private reDocComment : Set reDocComment = CompileRegExp("^[ \t]*('!.*)", True, True)

'! Dictionary listing the tags that VBSdoc accepts.
Private isValidTag : Set isValidTag = CreateObject("Scripting.Dictionary")
	isValidTag.Add "@author" , True
	isValidTag.Add "@brief"  , True
	isValidTag.Add "@date"   , True
	isValidTag.Add "@details", True
	isValidTag.Add "@param"  , True
	isValidTag.Add "@raise"  , True
	isValidTag.Add "@return" , True
	isValidTag.Add "@see"    , True
	isValidTag.Add "@todo"   , True
	isValidTag.Add "@version", True

Private localize : Set localize = CreateObject("Scripting.Dictionary")
	' English localization
	localize.Add "en", CreateObject("Scripting.Dictionary")
		localize("en").Add "AUTHOR"          , "Author"
		localize("en").Add "CLASS"           , "Class"
		localize("en").Add "CLASSES"         , "Classes"
		localize("en").Add "CLASS_SUMMARY"   , "Classes Summary"
		localize("en").Add "CONST_DETAIL"    , "Global Constant Detail"
		localize("en").Add "CONST_SUMMARY"   , "Global Constant Summary"
		localize("en").Add "CTORDTOR_DETAIL" , "Constructor/Destructor Detail"
		localize("en").Add "CTORDTOR_SUMMARY", "Constructor/Destructor Summary"
		localize("en").Add "DATE"            , "Date"
		localize("en").Add "EXCEPT"          , "Raises"
		localize("en").Add "FIELD_DETAIL"    , "Field Detail"
		localize("en").Add "FIELD_SUMMARY"   , "Field Summary"
		localize("en").Add "GLOBAL_CONST"    , "Global Constants"
		localize("en").Add "GLOBAL_PROC"     , "Global Procedures &amp; Functions"
		localize("en").Add "GLOBAL_VAR"      , "Global Variables"
		localize("en").Add "HTML_HELP_LANG"  , "0x409 Englisch (USA)"
		localize("en").Add "INDEX"           , "Global Index"
		localize("en").Add "METHOD_DETAIL"   , "Method Detail"
		localize("en").Add "METHOD_SUMMARY"  , "Method Summary"
		localize("en").Add "PARAM"           , "Parameters"
		localize("en").Add "PROC_DETAIL"     , "Global Procedure Detail"
		localize("en").Add "PROC_SUMMARY"    , "Global Procedure Summary"
		localize("en").Add "PROP_DETAIL"     , "Property Detail"
		localize("en").Add "PROP_SUMMARY"    , "Property Summary"
		localize("en").Add "RETURN"          , "Returns"
		localize("en").Add "SEE_ALSO"        , "See also"
		localize("en").Add "SOURCEFILE"      , "Source file"
		localize("en").Add "SOURCEINDEX"     , "Source File Index"
		localize("en").Add "TODO"            , "ToDo List"
		localize("en").Add "VAR_DETAIL"      , "Global Variable Detail"
		localize("en").Add "VAR_SUMMARY"     , "Global Variable Summary"
		localize("en").Add "VERSION"         , "Version"
	' Deutsche Lokalisierung
	localize.Add "de", CreateObject("Scripting.Dictionary")
		localize("de").Add "AUTHOR"          , "Autor"
		localize("de").Add "CLASS"           , "Klasse"
		localize("de").Add "CLASSES"         , "Klassen"
		localize("de").Add "CLASS_SUMMARY"   , "Klassen - Zusammenfassung"
		localize("de").Add "CONST_DETAIL"    , "Globale Konstanten - Details"
		localize("de").Add "CONST_SUMMARY"   , "Globale Konstanten - Zusammenfassung"
		localize("de").Add "CTORDTOR_DETAIL" , "Konstruktor/Destruktor - Details"
		localize("de").Add "CTORDTOR_SUMMARY", "Konstruktor/Destruktor - Zusammenfassung"
		localize("de").Add "DATE"            , "Datum"
		localize("de").Add "EXCEPT"          , "Wirft"
		localize("de").Add "FIELD_DETAIL"    , "Attribute - Details"
		localize("de").Add "FIELD_SUMMARY"   , "Attribute - Zusammenfassung"
		localize("de").Add "GLOBAL_CONST"    , "Globale Konstanten"
		localize("de").Add "GLOBAL_PROC"     , "Globale Prozeduren &amp; Funktionen"
		localize("de").Add "GLOBAL_VAR"      , "Globale Variablen"
		localize("de").Add "HTML_HELP_LANG"  , "0x407 Deutsch (Deutschland)"
		localize("de").Add "INDEX"           , "&Uuml;bersicht"
		localize("de").Add "METHOD_DETAIL"   , "Methoden - Details"
		localize("de").Add "METHOD_SUMMARY"  , "Methoden - Zusammenfassung"
		localize("de").Add "PARAM"           , "Parameter"
		localize("de").Add "PROC_DETAIL"     , "Globale Prozeduren - Details"
		localize("de").Add "PROC_SUMMARY"    , "Global Prozeduren - Zusammenfassung"
		localize("de").Add "PROP_DETAIL"     , "Eigenschaften - Details"
		localize("de").Add "PROP_SUMMARY"    , "Eigenschaften - Zusammenfassung"
		localize("de").Add "RETURN"          , "R&uuml;ckgabewert"
		localize("de").Add "SEE_ALSO"        , "Siehe auch"
		localize("de").Add "SOURCEFILE"      , "Quelldatei"
		localize("de").Add "SOURCEINDEX"     , "Index der Quelldateien"
		localize("de").Add "TODO"            , "Aufgabenliste"
		localize("de").Add "VAR_DETAIL"      , "Globale Variablen - Details"
		localize("de").Add "VAR_SUMMARY"     , "Globale Variablen - Zusammenfassung"
		localize("de").Add "VERSION"         , "Version"
	' Tradu��o em Portugu�s de Portugal
	localize.Add "pt", CreateObject("Scripting.Dictionary")
		localize("pt").Add "AUTHOR"          , "Autor"
		localize("pt").Add "CLASS"           , "Classe"
		localize("pt").Add "CLASSES"         , "Classes"
		localize("pt").Add "CLASS_SUMMARY"   , "Sum&aacute;rio das Classes"
		localize("pt").Add "CONST_DETAIL"    , "Detalhes das Constantes Globais"
		localize("pt").Add "CONST_SUMMARY"   , "Sum&aacute;rio das Constantes Globais"
		localize("pt").Add "CTORDTOR_DETAIL" , "Detalhes dos Constructores/Destructores"
		localize("pt").Add "CTORDTOR_SUMMARY", "Sum&aacute;rio dos Constructores/Destructores"
		localize("pt").Add "DATE"            , "Data"
		localize("pt").Add "EXCEPT"          , "Excep&ccedil;&atilde;o"
		localize("pt").Add "FIELD_DETAIL"    , "Detalhes do Atributo"
		localize("pt").Add "FIELD_SUMMARY"   , "Sum&aacute;rio do Atributo"
		localize("pt").Add "GLOBAL_CONST"    , "Constantes Globais"
		localize("pt").Add "GLOBAL_PROC"     , "Procedimentos Globais"
		localize("pt").Add "GLOBAL_VAR"      , "Vari&aacute;veis Globais"
		localize("pt").Add "HTML_HELP_LANG"  , "0x816 Portugu&ecirc;s (Portugal)"
		localize("pt").Add "INDEX"           , "&Iacute;ndice"
		localize("pt").Add "METHOD_DETAIL"   , "Detalhes de M&eacute;todos"
		localize("pt").Add "METHOD_SUMMARY"  , "Sum&aacute;rio de M&eacute;todos"
		localize("pt").Add "PARAM"           , "Par&acirc;metros"
		localize("pt").Add "PROC_DETAIL"     , "Detalhes de Procedimentos Globais"
		localize("pt").Add "PROC_SUMMARY"    , "Sum&aacute;rio de Procedimentos Globais"
		localize("pt").Add "PROP_DETAIL"     , "Detalhes de Propriedades Globais"
		localize("pt").Add "PROP_SUMMARY"    , "Sum&aacute;rio de Propriedades Globais"
		localize("pt").Add "RETURN"          , "Retornos"
		localize("pt").Add "SEE_ALSO"        , "Consulta adicional"
		localize("pt").Add "SOURCEFILE"      , "Ficheiro Fonte"
		localize("pt").Add "SOURCEINDEX"     , "&Iacute;ndice Principal"
		localize("pt").Add "TODO"            , "POR FAZER"
		localize("pt").Add "VAR_DETAIL"      , "Detalhes das Vari&aacute;veis Globais"
		localize("pt").Add "VAR_SUMMARY"     , "Sum&aacute;rio das Vari&aacute;veis Globais"
		localize("pt").Add "VERSION"         , "Vers&atilde;o"

Private beQuiet     '! Controls whether or not info and warning messages are printed.
Private projectName '! An optional project name.
Private anchors     '! Referenceable documentation items.
Private ext         '! Process files with this extension.

Main WScript.Arguments


'! The starting point. Evaluates commandline arguments, initializes
'! global variables and starts the documentation generation.
'!
'! @param  args   The list of arguments passed to the script.
Public Sub Main(args)
	Dim lang, includePrivate, chmFile, srcRoot, docRoot, doc
	Dim docTitle, name

	' initialize global variables/settings with default values
	beQuiet = False
	clog.Debug = False
	projectName = ""

	' initialize local variables with default values
	lang = DefaultLanguage
	includePrivate = False
	chmFile = ""

	' evaluate commandline arguments
	With args
		If .Named.Exists("?") Then PrintUsage(0)

		If .Named.Exists("d") Then clog.Debug = True
		If .Named.Exists("a") Then includePrivate = True
		If .Named.Exists("q") And Not clog.Debug Then beQuiet = True
		If .Named.Exists("p") Then projectName = .Named("p")
		If .Named.Exists("h") Then
			If Trim(.Named("h")) <> "" Then
				chmFile = Trim(.Named("h"))
			Else
				PrintUsage(1)
			End If
		End If

		' Process files with the default extension if /e is omitted or used without
		' specifying a particular extension. Otherwise process files with the given
		' extension.
		ext = DefaultExtension
		If .Named.Exists("e") Then
			If Trim(.Named("e")) <> "" Then
				ext = Trim(.Named("e"))
			End If
		End If

		' Use the default language if /l is omitted or used without specifying a
		' particular language. Use the given language if it exists in localize.Keys.
		' Otherwise print an error message and exit.
		If .Named.Exists("l") Then
			If localize.Exists(.Named("l")) Then
				lang = .Named("l")
			ElseIf .Named("l") <> "" Then
				clog.LogError .Named("l") & " is not a supported Language. Valid languages are: " _
					& Join(Sort(localize.Keys), ", ")
				WScript.Quit(1)
			End If
		End If

		If .Named.Exists("i") Then
			If Trim(.Named("i")) = "" Then
				clog.LogError "Empty value for option /i."
				WScript.Quit(1)
			Else
				srcRoot = .Named("i")
			End If
		Else
			PrintUsage(1)
		End If

		If .Named.Exists("o") Then
			docRoot = .Named("o")
		Else
			PrintUsage(1)
		End If
	End With

	clog.LogDebug "beQuiet:        " & beQuiet
	clog.LogDebug "projectName:    " & projectName
	clog.LogDebug "lang:           " & lang
	clog.LogDebug "includePrivate: " & includePrivate
	clog.LogDebug "srcRoot:        " & srcRoot
	clog.LogDebug "docRoot:        " & docRoot

	' extract the data
	Set doc = CreateObject("Scripting.Dictionary")

	If fso.FileExists(srcRoot) Then
		doc.Add "", GetFileDef(srcRoot, includePrivate)
		docTitle = fso.GetFileName(srcRoot)
	Else
		GetDef doc, fso.GetFolder(srcRoot), "", includePrivate
		docTitle = Null
	End If

	For Each name In doc.Keys
		If doc(name) Is Nothing Then doc.Remove(name)
	Next

	' generate the documentation
	Set anchors = ExtractAnchors(doc)
	For Each name In anchors.Keys
		clog.LogDebug name & vbTab & "-> " & anchors(name)
	Next

	GenDoc doc, docRoot, lang, docTitle
	If chmFile <> "" Then GenHTMLHelp chmFile, docRoot, lang

	WScript.Quit(0)
End Sub

' ------------------------------------------------------------------------------
' Data gathering
' ------------------------------------------------------------------------------

' During the data gathering phase the documentation data and metadata is
' gathered into data structures as lined out below. Square brackets indicate
' arrays, curly brackets indicate dictionaries. Elements in double quotes are
' name literals. Leaf elements are data types.
'
' {
' outdir = {
'          "Metadata"   = tags
'          "Todo"       = [ string ]
'          "Classes"    = {
'                         name = {
'                                "Metadata"    = tags
'                                "Constructor" = {
'                                                "Parameters" = []
'                                                "IsPrivate"  = boolean
'                                                "Metadata"   = tags
'                                                }
'                                "Destructor"  = {
'                                                "Parameters" = []
'                                                "IsPrivate"  = boolean
'                                                "Metadata"   = tags
'                                                }
'                                "Properties"  = {
'                                                name = {
'                                                       "Readable"   = boolean
'                                                       "Writable"   = boolean
'                                                       "Parameters" = [ string ]
'                                                       "IsPrivate"  = False
'                                                       "IsDefault"  = boolean
'                                                       "Metadata"   = tags
'                                                       }
'                                                }
'                                "Methods"     = {
'                                                name = {
'                                                       "Parameters" = [ string ]
'                                                       "IsPrivate"  = boolean
'                                                       "IsDefault"  = boolean
'                                                       "Metadata"   = tags
'                                                       }
'                                                }
'                                "Fields"      = {
'                                                name = {
'                                                       "IsPrivate" = boolean
'                                                       "Metadata"  = tags
'                                                       }
'                                                }
'                                }
'                         }
'          "Procedures" = {
'                         name = {
'                                "Parameters" = [ string ]
'                                "IsPrivate"  = boolean
'                                "IsDefault"  = boolean
'                                "Metadata"   = tags
'                                }
'                         }
'          "Constants"  = {
'                         name = {
'                                "Value"     = primitive
'                                "IsPrivate" = boolean
'                                "Metadata"  = tags
'                                }
'                         }
'          "Variables"  = {
'                         name = {
'                                "IsPrivate" = boolean
'                                "Metadata"  = tags
'                                }
'                         }
' }
'
' tags = {
'        "@author"  = [ string ]
'        "@brief"   = string
'        "@date"    = string
'        "@detail"  = string
'        "@param"   = [ string ]
'        "@raise"   = [ string ]
'        "@return"  = string
'        "@see"     = [ string ]
'        "@version" = string
'        }

'! Recursively traverse all subdirecotries of the given srcDir and extract
'! documentation information from all VBS files. If includePrivate is set
'! to True, then documentation for private elements is generated as well,
'! otherwise only public elements are included in the documentation.
'!
'! @param  doc            Reference to the dictionary containing the
'!                        documentation elements extracted from the source
'!                        files.
'! @param  srcDir         Directory containing the source files for the
'!                        documentation generation.
'! @param  docDir         Path relative to the documentation root directory
'!                        where the documentation for the files in srcDir
'!                        should be generated.
'! @param  includePrivate Include documentation for private elements.
Public Sub GetDef(ByRef doc, srcDir, docDir, includePrivate)
	Dim f, name, srcFile, dir

	clog.LogDebug "> GetDef(" & TypeName(doc) & ", " & TypeName(srcDir) & ", " & TypeName(docDir) & ", " & TypeName(includePrivate) & ")"

	For Each f In srcDir.Files
		clog.LogDebug "Extracting data from " & fso.BuildPath(srcDir, f.Name) & " ..."
		If LCase(fso.GetExtensionName(f.Name)) = ext Then
			name = Replace(fso.BuildPath(docDir, fso.GetBaseName(f.Name)), "\", "/")
			srcFile = fso.BuildPath(f.ParentFolder, f.Name)
			doc.Add name, GetFileDef(srcFile, includePrivate)
		End If
	Next

	For Each dir In srcDir.SubFolders
		clog.LogDebug "Recursing into subdir " & fso.BuildPath(srcDir, dir.Name) & " ..."
		GetDef doc, dir, fso.BuildPath(docDir, dir.Name), includePrivate
	Next
End Sub

'! Extract documentation information from a file. If includePrivate is set to
'! True, then documentation data for private elements is gathered as well,
'! otherwise only public elements are included in the documentation.
'!
'! @param  filename       Name of the source file for documentation generation.
'! @param  includePrivate Include documentation for private elements.
'! @return Dictionary describing structural and metadata elements in the given
'!         source file.
Public Function GetFileDef(filename, includePrivate)
	Dim outDir, inFile, content, m, line, globalComments, document

	clog.LogDebug "> GetFileDef(" & TypeName(filename) & ", " & TypeName(includePrivate) & ")"

	Set GetFileDef = Nothing
	If fso.GetFile(filename).Size = 0 Or Not fso.FileExists(filename) Then
		If fso.FileExists(filename) Then
			clog.LogDebug "File " & filename & " has size 0."
		Else
			clog.LogDebug "File " & filename & " does not exist."
		End If
		Exit Function ' nothing to do
	End If

	If Not beQuiet Then clog.LogInfo "Generating documentation for " & filename & " ..."

	content = GetContent(filename)

	' ****************************************************************************
	' preparatory steps
	' ****************************************************************************

	' Convert all linebreaks to LF, otherwise regular expressions might produce
	' strings with a trailing CR.
	content = Replace(Replace(content, vbNewLine, vbLf), vbCr, vbLf)

	' Join continued lines.
	content = reLineCont.Replace(content, " ")

	' Move End-of-Line doc comments to front.
	For Each m In reEOLComment.Execute(content)
		With m.SubMatches
			' Move doc comment to front only if the substring left of the doc comment
			' signifier ('!) contains an even number of double quotes. Otherwise the
			' signifier is inside a string, i.e. does not start an actual doc comment.
			If (Len(.Item(1)) - Len(Replace(.Item(1), """", ""))) Mod 2 = 0 Then
				content = Replace(content, m, vbLf & .Item(2) & vbLf & .Item(1), 1, 1)
			End If
		End With
	Next

	' ****************************************************************************
	' parsing the content starts here
	' ****************************************************************************

	Set document = CreateObject("Scripting.Dictionary")

	document.Add "Todo", GetTodoList(content)
	document.Add "Classes", GetClassDef(content, includePrivate)
	document.Add "Procedures", GetMethodDef(content, includePrivate)
	document.Add "Constants", GetConstDef(content, includePrivate)
	document.Add "Variables", GetVariableDef(content, includePrivate)

	' process file-global doc comments
	globalComments = ""
	For Each line In Split(content, vbLf)
		If reDocComment.Test(line) Then globalComments = globalComments & reDocComment.Replace(line, "$1") & vbLf
	Next
	document.Add "Metadata", ProcessComments(globalComments)

	CheckRemainingCode content

	Set GetFileDef = document
End Function

'! Get the content of a given input file. The function reads ASCII, 
'! UTF-8, and UTF-16 (big and little endian) encoded files. The encoding
'! is determined by the byte order mark (BOM) in the first 2 or 3 bytes
'! of the file.
'!
'! @param filename
'! @return The content of the input file
Private Function GetContent(filename)
	Dim bom, f, stream

	clog.LogDebug "Reading " & filename & " ..."

	bom = ""
	Set f = fso.OpenTextFile(filename)
	Do Until f.AtEndOfStream Or bom = "��" Or bom = "��" Or Len(bom) >= 3
		bom = bom & f.Read(1)
	Loop
	f.Close

	Select Case bom
		Case "��", "��"
			'UTF-16 text
			clog.LogDebug "Encoding: UTF-16"
			Set f = fso.OpenTextFile(filename, 1, False, -1)
			GetContent = f.ReadAll
			f.Close
		Case "﻿"
			'UTF-8 text
			clog.LogDebug "Encoding: UTF-8"
			Set stream = CreateObject("ADODB.Stream")
			stream.Open
			stream.Type = 2
			stream.Charset = "utf-8"
			stream.LoadFromFile filename
			GetContent = stream.ReadText
			stream.Close
		Case Else
			'ASCII text
			clog.LogDebug "Encoding: ASCII"
			Set f = fso.OpenTextFile(filename, 1, False, 0)
			GetContent = f.ReadAll
			f.Close
	End Select
End Function

'! Get a list of todo items. The list is generated from the @todo tags in the
'! code.
'!
'! @param  code   code fragment to check for @todo items.
'! @return A list with the todo items from the code.
Private Function GetTodoList(ByRef code)
	Dim list, m, line

	clog.LogDebug "> GetTodoList(" & TypeName(code) & ")"

	list = Array()

	For Each m in reTodo.Execute(code)
		ReDim Preserve list(UBound(list)+1)
		list(UBound(list)) = ""
		For Each line In Split(m.SubMatches.Item(0), vbLf)
			list(UBound(list)) = Trim(list(UBound(list)) & " " _
				& Trim(Replace(Replace(line, vbTab, " "), "'!", "")))
		Next
	Next
	code = reTodo.Replace(code, "")

	GetTodoList = list
End Function

'! Extract definitions of classes from the given code fragment.
'!
'! @param  code           Code fragment containing the class implementation.
'! @param  includePrivate Include private members/methods in the documentation.
'! @return Dictionary of dictionaries describing the class(es). The keys of
'!         the main dictionary are the names of the classes, which point to
'!         sub-dictionaries containing the definition data.
Private Function GetClassDef(ByRef code, ByVal includePrivate)
	Dim m, classBody, d

	clog.LogDebug "> GetClassDef(" & TypeName(code) & ", " & TypeName(includePrivate) & ")"

	Dim classes : Set classes = CreateObject("Scripting.Dictionary")

	For Each m In reClass.Execute(code)
		With m.SubMatches
			classBody = .Item(4)

			Set d = CreateObject("Scripting.Dictionary")
			d.Add "Metadata", ProcessComments(.Item(1))
			d.Add "Constructor", GetCtorDtorDef(classBody, includePrivate, True)
			d.Add "Destructor", GetCtorDtorDef(classBody, includePrivate, False)
			d.Add "Properties", GetPropertyDef(classBody)
			d.Add "Methods", GetMethodDef(classBody, includePrivate)
			d.Add "Fields", GetVariableDef(classBody, includePrivate)

			clog.LogDebug "Adding class " & .Item(3)
			classes.Add .Item(3), d
		End With
	Next
	code = reClass.Replace(code, vbLf)

	Set GetClassDef = classes
End Function

'! Extract definitions of constructor or destructor from the given code
'! fragment.
'!
'! @param  code           Code fragment containing constructor/destructor.
'! @param  includePrivate Include definition of private constructor or
'!                        destructor as well.
'! @param  returnCtor     If true, the function will return the constructor
'!                        definition, otherwise the destructor definition.
'! @return Dictionary describing constructor or destructor.
Private Function GetCtorDtorDef(ByRef code, ByVal includePrivate, ByVal returnCtor)
	Dim re, descr, m, isPrivate, tags, methodRedefined

	clog.LogDebug "> GetCtorDtorDef(" & TypeName(code) & ", " & TypeName(includePrivate) & ", " & TypeName(returnCtor) & ")"

	Dim method : Set method = CreateObject("Scripting.Dictionary")

	If returnCtor Then
		Set re = reCtor
		descr = "constructor"
	Else
		Set re = reDtor
		descr = "destructor"
	End If

	For Each m In re.Execute(code)
		With m.SubMatches
			isPrivate = CheckIfPrivate(.Item(4))
			If Not isPrivate Or includePrivate Then
				clog.LogDebug "Adding " & descr
				Set tags = ProcessComments(.Item(1))
				CheckConsistency .Item(5), Array(), tags, "sub"

				On Error Resume Next
				method.Add "Parameters", Array()
				method.Add "IsPrivate", isPrivate
				method.Add "Metadata", tags
				If Err.Number <> 0 Then
					If Err.Number = 457 Then
						' key is already present in dictionary
						methodRedefined = True
						' overwrite previous definition data ("last match wins")
						' no need to overwrite "Parameters", though, because those are
						' always [] for constructor as well as destructor
						method("IsPrivate") = isPrivate
						Set method("Metadata") = tags
					Else
						clog.LogError "Error storing " & descr & " data: " & FormatErrorMessage(Err)
					End If
				End If
				On Error Goto 0
			End If
		End With
	Next
	code = re.Replace(code, vbLf)

	If methodRedefined And Not beQuiet Then clog.LogWarning "Multiple " & descr _
		& " definitions. Using the last one."

	Set GetCtorDtorDef = method
End Function

'! Extract definitions of class methods and global procedures from the given
'! code fragment.
'!
'! @param  code           Code fragment containing the methods/procedures.
'! @param  includePrivate Include definitions of private methods as well.
'! @return Dictionary of dictionaries describing the methods. The keys of
'!         the main dictionary are the names of the methods, which point to
'!         sub-dictionaries containing the definition data.
Private Function GetMethodDef(ByRef code, ByVal includePrivate)
	Dim m, isPrivate, params, tags, d

	clog.LogDebug "> GetMethodDef(" & TypeName(code) & ", " & TypeName(includePrivate) & ")"

	Dim methods : Set methods = CreateObject("Scripting.Dictionary")

	For Each m In reMethod.Execute(code)
		With m.SubMatches
			isPrivate = CheckIfPrivate(.Item(4))
			If Not isPrivate Or includePrivate Then
				params = ExtractParameterNames(.Item(8))

				Set tags = ProcessComments(.Item(1))
				CheckConsistency .Item(7), params, tags, .Item(6)

				Set d = CreateObject("Scripting.Dictionary")
				d.Add "Parameters", params
				d.Add "IsPrivate", isPrivate
				d.Add "IsDefault", LCase(Trim(Replace(.Item(5), vbTab, ""))) = "default"
				d.Add "Metadata", tags

				clog.LogDebug "Adding procedure/function " & .Item(7)
				If methods.Exists(.Item(7)) Then
					clog.LogWarning .Item(6) & " " & .Item(7) & "() redefined."
				Else
					methods.Add .Item(7), d
				End If
			End If
		End With
	Next
	code = reMethod.Replace(code, vbLf)

	Set GetMethodDef = methods
End Function

'! Extract definitons of class properties. Private getter and setter methods
'! are disregarded, because even with the method present, the property would
'! not be readable/writable from an interface point of view.
'!
'! @param  code   Code fragment containing class properties.
'! @return Dictionary of dictionaries describing the properties. The keys of
'!         the main dictionary are the names of the properties, which point to
'!         sub-dictionaries containing the definition data.
Private Function GetPropertyDef(ByRef code)
	Dim defaultProperty, m, name, d, undocumented, arr, param

	clog.LogDebug "> GetPropertyDef(" & TypeName(code) & ")"

	Dim properties : Set properties = CreateObject("Scripting.Dictionary")
	Dim readable   : Set readable = CreateObject("Scripting.Dictionary")
	Dim writable   : Set writable = CreateObject("Scripting.Dictionary")

	For Each m In reProperty.Execute(code)
		With m.SubMatches
			If Not CheckIfPrivate(.Item(4)) Then
				' Private getter and setter methods are disregarded, because even with
				' the method present, the property is not readable/writable from an
				' interface point of view.
				If LCase(.Item(6)) = "get" Then
					' getter function
					readable.Add .Item(7), Array(.Item(1), ExtractParameterNames(.Item(8)))
				Else
					' setter function(s)
					' there can be two: "Set" for objects, "Let" for values
					If Not writable.Exists(.Item(7)) Then
						writable.Add .Item(7), Array(.Item(1), ExtractParameterNames(.Item(8)))
					Else
						' Append additional doc comments for the second setter function,
						' but omit the second parameter set (for simplicity).
						writable(.Item(7))(0) = writable(.Item(7))(0) & .Item(1)
					End If
				End If
				If LCase(Trim(Replace(.Item(5), vbTab, ""))) = "default" Then defaultProperty = .Item(7)
			End If
		End With
	Next
	code = reProperty.Replace(code, vbLf)

	' Add readable properties to the result dictionary. Set writable status
	' according to the property name's presence in the "writable" dictionary
	' and remove matching properties from the latter dictionary.
	For Each name In readable.Keys
		Set d = CreateObject("Scripting.Dictionary")
		d.Add "Readable", True
		If writable.Exists(name) Then
			d.Add "Writable", True
			d.Add "Metadata", ProcessComments(readable(name)(0) & writable(name)(0))
			CheckPropParamConsistency readable(name)(1), d("Metadata")("@param"), name, True
			CheckPropParamConsistency writable(name)(1), d("Metadata")("@param"), name, False
			writable.Remove(name)
		Else
			d.Add "Writable", False
			d.Add "Metadata", ProcessComments(readable(name)(0))
			CheckPropParamConsistency readable(name)(1), d("Metadata")("@param"), name, True
		End If
		d.Add "Parameters", readable(name)(1) ' readable(name) knows the actual parameter(s) in both cases, so we can use that
		d.Add "IsPrivate", False
		d.Add "IsDefault", name = defaultProperty
		clog.LogDebug "Adding property " & name
		properties.Add name, d
	Next

	' At this point the "writable" dictionary contains only properties that are
	' not present in the "readable" dictionary, so we can process those as
	' write-only properties.
	For Each name In writable.Keys
		Set d = CreateObject("Scripting.Dictionary")
		d.Add "Readable", False
		d.Add "Writable", True
		d.Add "IsPrivate", False
		d.Add "IsDefault", name = defaultProperty
		d.Add "Metadata", ProcessComments(writable(name)(0))

		CheckPropParamConsistency writable(name)(1), d("Metadata")("@param"), name, False

		' Writable properties have at least one parameter (the value passed to the
		' property). However, that parameter should not be part of the interface
		' documentation, and should thus be removed from the parameter list. Since
		' a writable property should have exactly one undocumented parameter (the
		' one for passing values), we add all except for the first undocumented
		' parameter to the property's parameter list.
		undocumented = GetMissing(writable(name)(1), d("Metadata")("@param"))
		If UBound(undocumented) >= 0 Then
			arr = Array()
			For Each param In writable(name)(1)
				If LCase(param) <> LCase(undocumented(0)) Then
					ReDim Preserve arr(UBound(arr)+1)
					arr(UBound(arr)) = param
				End If
			Next
		Else
			arr = writable(name)(1)
		End If
		d.Add "Parameters", arr

		properties.Add name, d
	Next

	Set GetPropertyDef = properties
End Function

'! Extract definitions of variables from the given code fragment.
'!
'! @param  code           Code fragment containing variable declarations.
'! @param  includePrivate Include definitions of private variables as well.
'! @return Dictionary of dictionaries describing the variables. The keys of
'!         the main dictionary are the names of the variables, which point to
'!         sub-dictionaries containing the definition data.
Private Function GetVariableDef(ByRef code, ByVal includePrivate)
	Dim m, isPrivate, tags, vars, name, d

	clog.LogDebug "> GetVariableDef(" & TypeName(code) & ", " & TypeName(includePrivate) & ")"

	Dim variables : Set variables = CreateObject("Scripting.Dictionary")

	For Each m In reVar.Execute(code)
		With m.SubMatches
			isPrivate = CheckIfPrivate(.Item(3))
			If Not isPrivate Or includePrivate Then
				Set tags = ProcessComments(.Item(1))
				vars = .Item(4)
				' If the match contains a declaration/definition combination: remove the
				' definition part.
				If Left(.Item(8), 1) = ":" Then vars = Trim(Split(vars, ":")(0))
				CheckIdentifierTags vars, tags
				vars = Split(Replace(Replace(vars, vbTab, ""), " ", ""), ",")

				Set d = CreateObject("Scripting.Dictionary")
				d.Add "IsPrivate", isPrivate
				d.Add "Metadata", tags

				For Each name In vars
					clog.LogDebug "Adding variable " & name
					variables.Add name, d
				Next
			End If
		End With
	Next
	code = reVar.Replace(code, vbLf)

	Set GetVariableDef = variables
End Function

'! Extract definitions of (global) constants from the given code fragment.
'!
'! @param  code           Code fragment containing constant definitions.
'! @param  includePrivate Include definitions of private constants as well.
'! @return Dictionariy of dictionaries describing the constants. The keys of
'!         the main dictionary are the names of the constants, which point to
'!         sub-dictionaries containing the definition data.
Private Function GetConstDef(ByRef code, ByVal includePrivate)
	Dim m, isPrivate, tags, d

	clog.LogDebug "> GetConstDef(" & TypeName(code) & ", " & TypeName(includePrivate) & ")"

	Dim constants : Set constants = CreateObject("Scripting.Dictionary")

	For Each m In reConst.Execute(code)
		With m.SubMatches
			isPrivate = CheckIfPrivate(.Item(4))
			If Not isPrivate Or includePrivate Then
				Set tags = ProcessComments(.Item(1))
				CheckIdentifierTags .Item(5), tags

				Set d = CreateObject("Scripting.Dictionary")
				d.Add "Value", .Item(6)
				d.Add "IsPrivate", isPrivate
				d.Add "Metadata", tags

				clog.LogDebug "++ " & .Item(5)
				constants.Add .Item(5), d
			End If
		End With
	Next
	code = reConst.Replace(code, "")

	Set GetConstDef = constants
End Function

'! Parse the given comment and return a dictionary with all present tags and
'! their values. A line that does not begin with a tag is appended to the value
'! of the previous tag, or to "@details" if there was no previous tag. Values
'! of tags that can appear more than once (e.g. "@param", "@see", ...) are
'! stored in Arrays.
'!
'! @param  comments  The comments to parse.
'! @return Dictionary with tag/value pairs.
Private Function ProcessComments(ByVal comments)
	Dim line, re, myMatches, m, currentTag

	clog.LogDebug "> ProcessComments(" & TypeName(comments) & ")"

	Dim tags    : Set tags = CreateObject("Scripting.Dictionary")
	Dim authors : authors = Array()
	Dim params  : params  = Array()
	Dim errors  : errors  = Array()
	Dim refs    : refs    = Array()

	currentTag = Null
	For Each line in Split(comments, vbLf)
		line = Trim(Replace(line, vbTab, " "))

		Set re = CompileRegExp("'![ \t]*(@\w+)[ \t]*(.*)", True, True)
		Set myMatches = re.Execute(line)
		If myMatches.Count > 0 Then
			' line starts with a tag
			For Each m in myMatches
				currentTag = LCase(m.SubMatches(0))
				If Not isValidTag(currentTag) Then
					If Not beQuiet Then clog.LogWarning "Unknown tag " & currentTag & "."
				Else
					Select Case currentTag
						Case "@author" Append authors, m.SubMatches(1)
						Case "@param" Append params, m.SubMatches(1)
						Case "@raise" Append errors, m.SubMatches(1)
						Case "@see" Append refs, m.SubMatches(1)
						Case Else
							If tags.Exists(currentTag) Then
								' Re-definiton of a tag that's supposed to be unique per
								' documentation block may be undesired.
								If Not beQuiet Then clog.LogWarning "Duplicate definition of tag " & currentTag _
									& ": " & m.SubMatches(1)
								tags(currentTag) = m.SubMatches(1)
							Else
								tags.Add currentTag, m.SubMatches(1)
							End If
					End Select
				End If
			Next
		Else
			' line does not begin with a tag
			' => line must be either empty, first line of detail description, or
			'    continuation of previous line.
			line = Trim(Mid(line, 3))   ' strip '! from beginning of line
			If line = "" Then
				If currentTag = "@details" Then
					tags("@details") = tags("@details") & vbNewLine
				Else
					currentTag = Null
				End If
			Else
				' Make "@details" currentTag if currentTag is not set. Then append
				' comment text to currentTag.
				If IsNull(currentTag) Then currentTag = "@details"
				Select Case currentTag
					Case "@author" Append authors(UBound(authors)), line
					Case "@param" Append params(UBound(params)), line
					Case "@raise" Append errors(UBound(errors)), line
					Case "@see" Append refs(UBound(refs)), line
					Case Else
						If tags.Exists(currentTag) Then
							If currentTag = "@details" And Left(line, 2) = "- " Then
								' line is list element => new line
								tags(currentTag) = tags(currentTag) & vbNewLine & line
							Else
								' line is not a list element (or the continuation of a list
								' element) => append text
								tags(currentTag) = tags(currentTag) & " " & line
							End If
						Else
							tags.Add currentTag, line
						End If
				End Select
			End If
		End If
	Next

	If UBound(authors) > -1 Then tags.Add "@author", authors
	If UBound(params) > -1 Then tags.Add "@param", params
	If UBound(errors) > -1 Then tags.Add "@raise", errors
	If UBound(refs) > -1 Then tags.Add "@see", refs

	' Remove trailing whitespace from @details descriptions.
	Set re = CompileRegExp("\s+$", True, False)
	tags("@details") = re.Replace(tags("@details"), "")

	' If no short description was given, set it to the first sentence of the
	' long description (or the whole long description if the latter consists
	' of just a single sentence).
	' If no long description was given, set it to the short description.
	' Do nothing if neither short nor long description were given.
	If Not tags.Exists("@brief") And tags.Exists("@details") Then
		' First replace ellipses, so they won't get in the way of detecting the
		' end of a sentence.
		Set re = CompileRegExp("\.{3,}", True, True)
		tags("@details") = re.Replace(tags("@details"), "�")
		' Set the short description to the first sentence of the long description.
		re.Pattern = "([\s\S]*?[.!?])\s+[\s\S]*"
		tags.Add "@brief", re.Replace(tags("@details"), "$1")
		' Set the short description to the full long description if no first
		' sentence was matched.
		If tags("@brief") = "" Then tags("@brief") = tags("@details")
	ElseIf tags.Exists("@brief") And Not tags.Exists("@details") Then
		tags.Add "@details", tags("@brief")
	End If

	Set ProcessComments = tags
End Function

' ------------------------------------------------------------------------------
' Document generation
' ------------------------------------------------------------------------------

'! Generate the documentation from the extracted data.
'!
'! @param  doc      Structure containing the documentation elements extracted
'!                  from the source file(s).
'! @param  docRoot  Root directory for the documentation files.
'! @param  lang     Documentation language. All generated text that is not read
'!                  from the source document(s) is created in this language.
'! @param  title    Title of the documentation page when documentation for a
'!                  single source file is generated. Must be Null otherwise.
Private Sub GenDoc(doc, docRoot, lang, title)
	Dim indexFile, relPath, re, css, filename, f, dir, entry, name, section, isFirst

	clog.LogDebug "> GenDoc(" & TypeName(doc) & ", " & TypeName(docRoot) & ", " & TypeName(lang) & ", " & TypeName(title) & ")"

	CreateDirectory docRoot
	CreateStylesheet fso.BuildPath(docRoot, StylesheetName)

	If IsNull(title) Then GenMainIndex doc, docRoot, lang

	Set re = CompileRegExp("[^\\/]+[\\/]", True, True)

	For Each relPath In doc.Keys
		css = re.Replace(fso.BuildPath(relPath, StylesheetName), "../")
		dir = Replace(fso.BuildPath(docRoot, relPath), "/", "\")
		CreateDirectory dir

		filename = fso.BuildPath(relPath, IndexFileName)
		clog.LogDebug "Writing script documentation file " & filename & " ..."
		Set f = fso.OpenTextFile(fso.BuildPath(docRoot, filename), ForWriting, True)
		WriteHeader f, fso.GetFileName(relPath), css

		If IsNull(title) Then
			f.WriteLine "<h1>" & fso.GetFileName(relPath) & "." & ext & "</h1>"
		Else
			f.WriteLine "<h1>" & title & "</h1>"
		End If

		With doc(relPath)
			f.Write GenDetailsInfo(.Item("Metadata"))
			f.Write GenVersionInfo(.Item("Metadata"), lang)
			f.Write GenDateInfo(.Item("Metadata"), lang)
			f.Write GenAuthorInfo(.Item("Metadata"), lang)
			f.Write GenReferencesInfo(.Item("Metadata"), lang, filename)

			' Write ToDo list.
			If UBound(.Item("Todo")) > -1 Then
				f.WriteLine "<h2>" & EncodeHTMLEntities(localize(lang)("TODO")) & "</h2>" & vbNewLine & "<ul>"
				For Each entry In .Item("Todo")
					f.WriteLine "  <li>" & EncodeHTMLEntities(entry) & "</li>"
				Next
				f.WriteLine "</ul>"
			End If

			WriteSection f, filename, localize(lang)("CONST_SUMMARY"), .Item("Constants"), lang, "Constant", True
			WriteSection f, filename, localize(lang)("VAR_SUMMARY"), .Item("Variables"), lang, "Variable", True

			' Write class summary information.
			If .Item("Classes").Count > 0 Then
				f.WriteLine "<h2>" & EncodeHTMLEntities(localize(lang)("CLASS_SUMMARY")) & "</h2>"
				isFirst = True
				For Each entry In Sort(.Item("Classes").Keys)
					If isFirst Then
						isFirst = False
					Else
						f.WriteLine "<hr/>"
					End If
					f.WriteLine "<p><span class=""name""><a href=""" & EncodeHTMLEntities(entry) & ".html"">" _
						& EncodeHTMLEntities(entry) & "</a></span></p>"
					If .Item("Classes")(entry)("Metadata").Exists("@brief") Then f.WriteLine "<p class=""description"">" _
						& EncodeHTMLEntities(.Item("Classes")(entry)("Metadata")("@brief")) & "</p>"
				Next
			End If

			WriteSection f, filename, localize(lang)("PROC_SUMMARY"), .Item("Procedures"), lang, "Procedure", True
			WriteSection f, filename, localize(lang)("CONST_DETAIL"), .Item("Constants"), lang, "Constant", False
			WriteSection f, filename, localize(lang)("VAR_DETAIL"), .Item("Variables"), lang, "Variable", False
			WriteSection f, filename, localize(lang)("PROC_DETAIL"), .Item("Procedures"), lang, "Procedure", False
		End With

		WriteFooter f
		f.Close

		For Each name In doc(relPath)("Classes").Keys
			filename = fso.BuildPath(relPath, name & ".html")
			clog.LogDebug "Writing class documentation file " & filename & " ..."
			Set f = fso.OpenTextFile(fso.BuildPath(docRoot, filename), ForWriting, True)
			WriteHeader f, EncodeHTMLEntities(name), css

			With doc(relPath)("Classes")(name)
				f.WriteLine "<h1>" & EncodeHTMLEntities(localize(lang)("CLASS") & " " & name) & "</h1>"
				f.Write GenDetailsInfo(.Item("Metadata"))
				f.Write GenVersionInfo(.Item("Metadata"), lang)
				f.Write GenDateInfo(.Item("Metadata"), lang)
				f.Write GenAuthorInfo(.Item("Metadata"), lang)
				f.Write GenReferencesInfo(.Item("Metadata"), lang, filename)

				WriteSection f, filename, localize(lang)("FIELD_SUMMARY"), .Item("Fields"), lang, "Variable", True
				WriteSection f, filename, localize(lang)("PROP_SUMMARY"), .Item("Properties"), lang, "Property", True
				section = ""
				If .Item("Constructor").Count > 0 Then section = GenSummary("Class_Initialize", .Item("Constructor"), "Procedure")
				If .Item("Destructor").Count > 0 Then
					If section <> "" Then section = section & vbNewLine & "<hr/>" & vbNewLine
					section = section & GenSummary("Class_Terminate", .Item("Destructor"), "Procedure")
				End If
				If section <> "" Then f.WriteLine "<h2>" & EncodeHTMLEntities(localize(lang)("CTORDTOR_SUMMARY")) _
					& "</h2>" & vbNewLine & section
				WriteSection f, filename, localize(lang)("METHOD_SUMMARY"), .Item("Methods"), lang, "Procedure", True

				WriteSection f, filename, localize(lang)("FIELD_DETAIL"), .Item("Fields"), lang, "Variable", False
				WriteSection f, filename, localize(lang)("PROP_DETAIL"), .Item("Properties"), lang, "Property", False
				section = ""
				If .Item("Constructor").Count > 0 Then section = GenDetails("Class_Initialize", .Item("Constructor"), lang, "Procedure", filename)
				If .Item("Destructor").Count > 0 Then
					If section <> "" Then section = section & vbNewLine & "<hr/>" & vbNewLine
					section = section & GenDetails("Class_Terminate", .Item("Destructor"), lang, "Procedure", filename)
				End If
				If section <> "" Then f.WriteLine "<h2>" & EncodeHTMLEntities(localize(lang)("CTORDTOR_DETAIL")) _
					& "</h2>" & vbNewLine & section
				WriteSection f, filename, localize(lang)("METHOD_DETAIL"), .Item("Methods"), lang, "Procedure", False
			End With

			WriteFooter f
			f.Close
		Next
	Next
End Sub

'! Generate the main index for the documentation.
'!
'! @param  doc    Structure containing the documentation elements extracted
'!                from the source file(s).
'! @param  root   Root directory for the documentation files.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
Sub GenMainIndex(doc, root, lang)
	Dim indexFile, relPath
	Dim classes, constants, variables, procedures
	Dim name, signature, srcPath

	clog.LogDebug "Writing index file " & fso.BuildPath(root, IndexFileName) & " ..."

	Set indexFile = fso.OpenTextFile(fso.BuildPath(root, IndexFileName), ForWriting, True)

	WriteHeader indexFile, "Main Page", StylesheetName
	If projectName = "" Then
		indexFile.WriteLine "<h1>" & localize(lang)("INDEX") & "</h1>"
	Else
		indexFile.WriteLine "<h1>" & localize(lang)("INDEX") & ": " & projectName & "</h1>"
	End If

	Set classes    = CreateRecordset()
	Set constants  = CreateRecordset()
	Set variables  = CreateRecordset()
	Set procedures = CreateRecordset()

	For Each relPath In Sort(doc.Keys)
		srcPath = Replace(relPath & "." & Ext, "/", "\")
		For Each name In doc(relPath)("Classes").Keys
			classes.AddNew
			classes("name").Value = name
			classes("docpath").Value = relPath & "/" & name & ".html"
			classes("srcpath").Value = srcPath
			classes("description").Value = doc(relPath)("Classes")(name)("Metadata")("@brief")
			classes.Update
		Next
		classes.Sort = "name, srcpath ASC"
		For Each name In doc(relPath)("Constants").Keys
			constants.AddNew
			constants("name").Value = name
			constants("docpath").Value = relPath & "/" & IndexFileName & "#" & name
			constants("srcpath").Value = srcPath
			constants("description").Value = doc(relPath)("Constants")(name)("Metadata")("@brief")
			constants.Update
		Next
		constants.Sort = "name, srcpath ASC"
		For Each name In doc(relPath)("Variables").Keys
			variables.AddNew
			variables("name").Value = name
			variables("docpath").Value = relPath & "/" & IndexFileName & "#" & name
			variables("srcpath").Value = srcPath
			variables("description").Value = doc(relPath)("Variables")(name)("Metadata")("@brief")
			variables.Update
		Next
		variables.Sort = "name, srcpath ASC"
		For Each name In doc(relPath)("Procedures").Keys
			procedures.AddNew
			signature = name & "(" & Join(doc(relPath)("Procedures")(name)("Parameters"), ", ") & ")"
			procedures("name").Value = signature
			procedures("docpath").Value = relPath & "/" & IndexFileName & "#" & CanonicalizeID(signature)
			procedures("srcpath").Value = srcPath
			procedures("description").Value = doc(relPath)("Procedures")(name)("Metadata")("@brief")
			procedures.Update
		Next
		procedures.Sort = "name, srcpath ASC"
	Next

	indexFile.WriteLine GenGlobals(classes, "CLASSES", lang)
	classes.Close
	Set classes = Nothing

	indexFile.WriteLine GenGlobals(constants, "GLOBAL_CONST", lang)
	constants.Close
	Set constants = Nothing

	indexFile.WriteLine GenGlobals(variables, "GLOBAL_VAR", lang)
	variables.Close
	Set variables = Nothing

	indexFile.WriteLine GenGlobals(procedures, "GLOBAL_PROC", lang)
	procedures.Close
	Set procedures = Nothing

	indexFile.WriteLine "<h2>" & localize(lang)("SOURCEINDEX") & "</h2>"
	For Each relPath In Sort(doc.Keys)
		indexFile.WriteLine "<p><a href=""" & relPath & "/" & IndexFileName & """>" & relPath & "." & ext & "</a></p>"
	Next

	WriteFooter indexFile
	indexFile.Close
End Sub

'! Write the given heading and data to the given file. The heading omitted in
'! case it's Null, otherwise it is written as <h2>. The data is processed into
'! summary or detail information, depending on presence (or absence) of the
'! word "summary" in the heading.
'!
'! @param  file         Filehandle to write to.
'! @param  filename     Name and path of the documentation file that is
'!                      currently being created.
'! @param  heading      The heading for the given section.
'! @param  data         Data (sub-)structure containing the elements of the
'!                      section.
'! @param  lang         Documentation language. All generated text that is not
'!                      read from the source document(s) is created in this
'!                      language.
'! @param  sectionType  The type of the section to be written (constant,
'!                      method, property, or variable)
'! @param  isSummary    If True, a summary section is generated, otherwise a
'!                      detail section.
Private Sub WriteSection(file, filename, heading, data, lang, sectionType, isSummary)
	Dim name, isFirst

	clog.LogDebug "> WriteSection(" & TypeName(file) & ", " & TypeName(heading) & ", " & TypeName(data) & ", " & TypeName(lang) & ", " & TypeName(sectionType) & ", " & TypeName(isSummary) & ")"

	If data.Count > 0 Then
		If Not IsNull(heading) Then file.WriteLine "<h2>" & EncodeHTMLEntities(heading) & "</h2>" & vbNewLine
		isFirst = True
		For Each name In Sort(data.Keys)
			If isFirst Then
				isFirst = False
			Else
				file.WriteLine "<hr/>"
			End If
			If isSummary Then
				file.WriteLine GenSummary(name, data(name), sectionType)
			Else
				file.WriteLine GenDetails(name, data(name), lang, sectionType, filename)
			End If
		Next
	End If
End Sub

'! Generate a compiled HTML Help file (.chm) from the HTML output. The HTML
'! Help Workshop must be installed, and the commandline HTML Help compiler
'! executable hhc.exe must be present in the %PATH% for this to work.
'!
'! @param  chmFile  Name and path of the compiled HTML file.
'! @param  docRoot  Root directory for the documentation files.
'! @param  lang     Documentation language. All generated text that is not read
'!                  from the source document(s) is created in this language.
'!
'! @see http://msdn.microsoft.com/en-us/library/ms670169.aspx
Private Sub GenHTMLHelp(chmFile, docRoot, lang)
	Dim name, projectFilename, contentsFilename, indexFilename
	Dim target, hh, hhc

	clog.LogDebug "> GenHTMLHelp(" & TypeName(chmFile) & ", " & TypeName(docRoot) & ", " & TypeName(lang) & ")"

	name = fso.GetBaseName(chmFile)

	projectFilename  = name & ".hhp"
	contentsFilename = name & ".hhc"
	indexFilename    = name & ".hhk"

	clog.LogDebug "Creating HTML Help project, contents, and index files:" & vbNewLine _
		& vbTab & projectFilename & vbNewLine _
		& vbTab & contentsFilename & vbNewLine _
		& vbTab & indexFilename
	Set hh = CreateObject("Scripting.Dictionary")
		hh.Add "project" , fso.OpenTextFile(projectFilename, ForWriting, True)
		hh.Add "contents", fso.OpenTextFile(contentsFilename, ForWriting, True)
		hh.Add "index"   , fso.OpenTextFile(indexFilename, ForWriting, True)

	hh("project").WriteLine "[OPTIONS]" & vbNewLine _
		& "Compatibility=1.1 or later" & vbNewLine _
		& "Compiled file=" & chmFile & vbNewLine _
		& "Contents file=" & contentsFilename & vbNewLine _
		& "Display compile progress=Yes" & vbNewLine _
		& "Index file=" & indexFilename & vbNewLine _
		& "Language=" & localize(lang)("HTML_HELP_LANG") & vbNewLine & vbNewLine _
		& "[FILES]"
	hh("contents").WriteLine "<!DOCTYPE HTML PUBLIC ""-//IETF//DTD HTML//EN"">" & vbNewLine _
		& "<HTML><HEAD>" & vbNewLine _
		& "<!-- Sitemap 1.0 -->" & vbNewLine _
		& "</HEAD><BODY>" & vbNewLine _
		& "<OBJECT type=""text/site properties"">" & vbNewLine _
		& "<param name=""ImageType"" value=""Folder"">" & vbNewLine _
		& "</OBJECT>"
	hh("index").WriteLine "<!DOCTYPE HTML PUBLIC ""-//IETF//DTD HTML//EN"">" & vbNewLine _
		& "<HTML><HEAD>" & vbNewLine _
		& "<!-- Sitemap 1.0 -->" & vbNewLine _
		& "</HEAD><BODY><UL>"

	CollectHelpContents docRoot, hh

	'! Generate index entries from anchors.
	For Each target In Sort(anchors.Items)
		hh("index").WriteLine "<LI><OBJECT type=""text/sitemap"">" & vbNewLine _
			& "<param name=""Name"" value=""" & Split(Mid(target, InStrRev(target, "#")+1), "(")(0) & """>" & vbNewLine _
			& "<param name=""Local"" value=""" & fso.BuildPath(docRoot, target) & """>" & vbNewLine _
			& "</OBJECT>"
	Next

	hh("project").WriteLine vbNewLine & "[INFOTYPES]" & vbNewLine
	hh("contents").WriteLine "</BODY></HTML>"
	hh("index").WriteLine "</UL></BODY></HTML>"

	hh("index").Close
	hh("contents").Close
	hh("project").Close

	clog.LogDebug "Running HTML Help compiler hhc.exe ..."
	Set hhc = sh.Exec("hhc.exe " & projectFilename)

	Do While hhc.Status = WshRunning
		WScript.Sleep 100
	Loop

	If Not beQuiet Then clog.LogInfo hhc.StdOut.ReadAll

	' Apparently hhc.exe returns 1 when finishing successfully.
	' For whatever reason.
	If hhc.ExitCode <> 1 Then clog.LogError Trim(hhc.StdErr.ReadAll & " (" & hhc.ExitCode & ")")
End Sub

'! Recursively traverse a directory tree and record the HTML files in the
'! project and contents file.
'!
'! @param  dir  The directory to process.
'! @param  hh   Dictionary with open handles to the project, contents and
'!              index files.
Sub CollectHelpContents(dir, hh)
	Dim fldr, d, f, ext, relPath, contents, title

	Set fldr = fso.GetFolder(dir)

	relPath = fso.BuildPath(dir, IndexFileName)
	hh("project").WriteLine relPath
	' ImageNumber 2 == book symbol
	hh("contents").WriteLine "<UL><LI><OBJECT type=""text/sitemap"">" & vbNewLine _
		& "<param name=""Name"" value=""" & GetSubject(relPath) & """>" & vbNewLine _
		& "<param name=""Local"" value=""" & relPath & """>" & vbNewLine _
		& "<param name=""ImageNumber"" value=""2"">" & vbNewLine _
		& "</OBJECT>"

	For Each d In fldr.SubFolders
		CollectHelpContents fso.BuildPath(dir, d.Name), hh
	Next

	contents = ""
	For Each f In fldr.Files
		ext = LCase(fso.GetExtensionName(f.Name))
		If ext = "htm" Or ext = "html" And fso.GetBaseName(f.Name) <> "index" Then
			relPath = fso.BuildPath(dir, f.Name)
			hh("project").WriteLine relPath
			' ImageNumber 11 == text file symbol
			contents = contents &  "<LI><OBJECT type=""text/sitemap"">" & vbNewLine _
				& "<param name=""Name"" value=""" & GetSubject(f.Path) & """>" & vbNewLine _
				& "<param name=""Local"" value=""" & relPath & """>" & vbNewLine _
				& "<param name=""ImageNumber"" value=""11"">" & vbNewLine _
				& "</OBJECT>" & vbNewLine
		End If
	Next
	If contents <> "" Then hh("contents").Write "<UL>" & contents & "</UL>"
	hh("contents").WriteLine "</UL>"
End Sub

' ------------------------------------------------------------------------------
' HTML code generation
' ------------------------------------------------------------------------------

'! Write HTML headers to the given file. The headers are parametrized with
'! title and stylesheet.
'!
'! @param  outFile    Handle to a file.
'! @param  title      Title of the HTML page
'! @param  stylesheet Path to the stylesheet for the HTML page.
Private Sub WriteHeader(outFile, title, stylesheet)
	clog.LogDebug "> WriteHeader(" & TypeName(outFile) & ", " & TypeName(title) & ", " & TypeName(stylesheet) & ")"
	clog.LogDebug "  title:      " & title
	clog.LogDebug "  stylesheet: " & stylesheet

	If projectName <> "" Then title = projectName & ": " & title
	outFile.WriteLine "<!DOCTYPE html PUBLIC ""-//W3C//DTD XHTML 1.0 Transitional//EN""" & vbNewLine _
		& vbTab & """http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd"">" & vbNewLine _
		& "<html>" & vbNewLine & "<head>" & vbNewLine _
		& "<title>" & title & "</title>" & vbNewLine _
		& "<meta name=""date"" content=""" & FormatDate(Now) & """ />" & vbNewLine _
		& "<meta http-equiv=""content-type"" content=""text/html; charset=iso-8859-1"" />" & vbNewLine _
		& "<meta http-equiv=""content-language"" content=""en"" />" & vbNewLine _
		& "<link rel=""stylesheet"" type=""text/css"" href=""" & stylesheet & """ />" & vbNewLine _
		& "</head>" & vbNewLine & "<body>"
End Sub

'! Write HTML closing tags to the given file.
'!
'! @param  outFile  Handle to a file.
Private Sub WriteFooter(outFile)
	outFile.WriteLine "<p class=""footer"">" & CopyrightInfo & "</p>" & vbNewLine _
		& "</body>" & vbNewLine & "</html>"
End Sub

'! Generate summary documentation. The documentation is generated in HTML
'! format.
'!
'! @param  name         Name of the processed element.
'! @param  properties   Dictionary with the properties of the processed
'!                      element.
'! @param elementType   The type of the processed element (constant, method,
'!                      property, or variable)
'! @return The summary documentation in HTML format.
Private Function GenSummary(ByVal name, ByVal properties, ByVal elementType)
	Dim signature, params, re

	clog.LogDebug "> GenSummary(" & TypeName(name) & ", " & TypeName(properties) & ", " & TypeName(elementType) & ")"
	clog.LogDebug "  name:        " & name
	clog.LogDebug "  properties:  " & Join(properties.Keys, ", ")
	clog.LogDebug "  elementType: " & elementType

	name = EncodeHTMLEntities(name)

	Select Case LCase(elementType)
	Case "constant"
		Set re = CompileRegExp("^&h([0-9a-f]+)$", True, True)
		signature = "<code><span class=""name""><a href=""#" & name & """>" & name _
			& "</a></span>: " & re.Replace(Trim(properties("Value")), "0x$1") & "</code>"
		GenSummary = GenSummaryInfo(signature, properties("Metadata"))
	Case "procedure"
		params = EncodeHTMLEntities(Join(properties("Parameters"), ", "))
		If properties("IsDefault") Then
			signature = "<code class=""default"">"
		Else
			signature = "<code>"
		End If
		signature = signature & "<span class=""name""><a href=""#" & CanonicalizeID(name _
			& "(" & params & ")") & """>" & name & "</a></span>(" & params & ")</code>"
		GenSummary = GenSummaryInfo(signature, properties("Metadata"))
	Case "property"
		If properties("IsDefault") Then
			signature = "<code class=""default"">"
		Else
			signature = "<code>"
		End If
		signature = signature & "<span class=""name""><a href=""#" _
			& CanonicalizeID(name) & """>" & name & "</a></span>"
		If properties.Exists("Parameters") Then
			If UBound(properties("Parameters")) >= 0 Then signature = signature & "(" _
				& EncodeHTMLEntities(Join(properties("Parameters"), ", ")) & ")"
		End If
		signature = signature & "</code>"
		GenSummary = GenSummaryInfo(signature, properties("Metadata"))
	Case "variable"
		signature = "<code><span class=""name""><a href=""#" & name & """>" & name _
			& "</a></span></code>"
		GenSummary = GenSummaryInfo(signature, properties("Metadata"))
	Case Else
		clog.LogError "Cannot generate summary information for unknown element type " & elementType & "."
	End Select
End Function

'! Generate detail documentation. The documentation is generated in HTML
'! format.
'!
'! @param  name       Name of the processed element.
'! @param  properties Dictionary with the properties of the processed
'!                    element.
'! @param  lang       Documentation language. All generated text that is not
'!                    read from the source document(s) is created in this
'!                    language.
'! @param elementType The type of the processed element (constant, method,
'!                    property, or variable)
'! @param  filename   Name and path of the documentation file that is currently
'!                    being created.
'! @return The detail documentation in HTML format.
Private Function GenDetails(ByVal name, ByVal properties, ByVal lang, ByVal elementType, ByVal filename)
	Dim heading, signature, params, visibility, accessibility, re

	clog.LogDebug "> GenDetails(" & TypeName(name) & ", " & TypeName(properties) & ", " & TypeName(lang) & ", " & TypeName(elementType) & ", " & TypeName(filename) & ")"
	clog.LogDebug "  name:        " & name
	clog.LogDebug "  properties:  " & Join(properties.Keys, ", ")
	clog.LogDebug "  lang:        " & lang
	clog.LogDebug "  elementType: " & elementType
	clog.LogDebug "  filename:    " & filename

	GenDetails = ""

	name = EncodeHTMLEntities(name)

	If LCase(elementType) = "procedure" Then
		params = EncodeHTMLEntities(Join(properties("Parameters"), ", "))
		heading = "<a id=""" & CanonicalizeID(name & "(" & params & ")") & """></a>" & name
	Else
		heading = "<a id=""" & CanonicalizeID(name) & """></a>" & name
	End If

	If properties("IsPrivate") Then
		visibility = "Private"
	Else
		visibility = "Public"
	End If

	Select Case LCase(elementType)
	Case "constant"
		Set re = CompileRegExp("^&h([0-9a-f]+)$", True, True)
		signature = "<code>" & visibility & " Const <span class=""name"">" & name _
			& "</span> = " & re.Replace(Trim(properties("Value")), "0x$1") & "</code>"
		GenDetails = GenDetailsHeading(heading, signature, properties("IsDefault")) _
			& GenDetailsInfo(properties("Metadata")) _
			& GenAuthorInfo(properties("Metadata"), lang) _
			& GenDateInfo(properties("Metadata"), lang) _
			& GenReferencesInfo(properties("Metadata"), lang, filename)
	Case "procedure"
		signature = "<code>" & visibility
		If properties("IsDefault") Then signature = signature & " Default"
		signature = signature & " <span class=""name"">" & name & "</span>(" & params & ")</code>"
		GenDetails = GenDetailsHeading(heading, signature, properties("IsDefault")) _
			& GenDetailsInfo(properties("Metadata")) _
			& GenParameterInfo(properties("Metadata"), lang) _
			& GenReturnValueInfo(properties("Metadata"), lang) _
			& GenExceptionInfo(properties("Metadata"), lang) _
			& GenAuthorInfo(properties("Metadata"), lang) _
			& GenDateInfo(properties("Metadata"), lang) _
			& GenReferencesInfo(properties("Metadata"), lang, filename)
	Case "property"
		If properties("Readable") Then
			If properties("Writable") Then
				accessibility = "read-write"
			Else
				accessibility = "read-only"
			End If
		Else
			If properties("Writable") Then
				accessibility = "write-only"
			Else
				clog.LogError "Property " & name & " is neither readable nor writable. This should never happen, since this kind of property is ignored by the document parser."
			End If
		End If
		signature = "<code><span class=""name"">" & name & "</span>"
		If properties.Exists("Parameters") Then
			If UBound(properties("Parameters")) >= 0 Then
				params = EncodeHTMLEntities(Join(properties("Parameters"), ", "))
				signature = signature & "(" & params & ")"
			End If
		End If
		signature = signature & "</code><br/>" & accessibility
		'~ If properties("IsDefault") Then signature = signature & ", default"
		GenDetails = GenDetailsHeading(heading, signature, properties("IsDefault")) _
			& GenDetailsInfo(properties("Metadata")) _
			& GenExceptionInfo(properties("Metadata"), lang) _
			& GenAuthorInfo(properties("Metadata"), lang) _
			& GenDateInfo(properties("Metadata"), lang) _
			& GenReferencesInfo(properties("Metadata"), lang, filename)
	Case "variable"
		signature = "<code>" & visibility & " <span class=""name"">" & name & "</span></code>"
		GenDetails = GenDetailsHeading(heading, signature, properties("IsDefault")) _
			& GenDetailsInfo(properties("Metadata")) _
			& GenAuthorInfo(properties("Metadata"), lang) _
			& GenDateInfo(properties("Metadata"), lang) _
			& GenReferencesInfo(properties("Metadata"), lang, filename)
	Case Else
		clog.LogError "Cannot generate detail information for unknown element type " & elementType & "."
	End Select
End Function

'! Generate author information from @author tags. Should the tag also contain
'! an e-mail address, that address is made into a hyperlink.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang     Documentation language. All generated text that is not read
'!                  from the source document(s) is created in this language.
'! @return HTML snippet with the author information.
Private Function GenAuthorInfo(tags, lang)
	Dim re, author
	Dim info : info = ""

	clog.LogDebug "> GenAuthorInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"

	If tags.Exists("@author") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("AUTHOR")) & ":</h4>" & vbNewLine
		Set re = CompileRegExp("\S+@\S+", True, True)
		For Each author In tags("@author")
			If re.Test(author) Then
				' author data contains e-mail address => create link
				info = info & "<p class=""value"">" & Trim(EncodeHTMLEntities(Trim(re.Replace(author, ""))) _
					& " &lt;" & CreateMailtoLink(re.Execute(author)(0))) & "&gt;</p>" & vbNewLine
			Else
				' author data does not contain e-mail address => use as-is
				info = info & "<p class=""value"">" & EncodeHTMLEntities(Trim(author)) & "</p>" & vbNewLine
			End If
		Next
	End If

	GenAuthorInfo = info
End Function

'! Generate references ("see also") information from @see tags. All values are
'! made into hyperlinks (either internal or external).
'!
'! @param  tags     Dictionary with the tag/value pairs from the documentation
'!                  header.
'! @param  lang     Documentation language. All generated text that is not read
'!                  from the source document(s) is created in this language.
'! @param  filename Name and path of the documentation file that is currently
'!                  being created.
'! @return HTML snippet with the references information.
Private Function GenReferencesInfo(tags, lang, filename)
	Dim ref, re, m
	Dim info : info = ""

	clog.LogDebug "> GenReferencesInfo(" & TypeName(tags) & ", " & TypeName(lang) & ", " & TypeName(filename) & ")"

	If tags.Exists("@see") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("SEE_ALSO")) & ":</h4>" & vbNewLine
		For Each ref In tags("@see")
			Set re = CompileRegExp("(\S+)(\s+.*)?", True, True)
			For Each m In re.Execute(ref)
				info = info & "<p class=""value"">" _
					& CreateLink(m.SubMatches(0), m.SubMatches(1), filename) _
					& "</p>" & vbNewLine
			Next
		Next
	End If

	GenReferencesInfo = info
End Function

'! Generate version information from the @version tag.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
'! @return HTML snippet with the version information.
Private Function GenVersionInfo(tags, lang)
	Dim info : info = ""

	clog.LogDebug "> GenVersionInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"

	If tags.Exists("@version") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("VERSION")) & ":</h4>" & vbNewLine _
			& "<p class=""value"">" & EncodeHTMLEntities(tags("@version")) & "</p>" & vbNewLine
	End If

	GenVersionInfo = info
End Function

'! Generate date information from the @date tag.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
'! @return HTML snippet with the date information.
Private Function GenDateInfo(tags, lang)
	Dim info : info = ""

	clog.LogDebug "> GenDateInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"

	If tags.Exists("@date") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("DATE")) & ":</h4>" & vbNewLine _
			& "<p class=""value"">" & EncodeHTMLEntities(tags("@date")) & "</p>" & vbNewLine
	End If

	GenDateInfo = info
End Function

'! Generate summary information from the @brief tag.
'!
'! @param  name   Name of the documented element.
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @return HTML snippet with the summary information. Empty string if no
'!         summary information was present.
Private Function GenSummaryInfo(name, tags)
	Dim summary

	clog.LogDebug "> GenSummaryInfo(" & TypeName(name) & ", " & TypeName(tags) & ")"

	summary = "<p class=""function"">" & name & "</p>" & vbNewLine
	If tags.Exists("@brief") Then summary = summary & "<p class=""description"">" _
		& EncodeHTMLEntities(tags("@brief")) & "</p>" & vbNewLine
	GenSummaryInfo = summary
End Function

'! Generate HTML code for heading and signature line in a "detail" section.
'! The heading is created as <h3>.
'!
'! @param  heading   The heading text.
'! @param  signature The signature of the procedure, variable or constant.
'! @param  default   Indicates whether the documented item is a default item or not.
'! @return HTML snippet with the heading and signature.
Private Function GenDetailsHeading(heading, signature, default)
	Dim tag

	If default Then
		tag = "<h3 class=""default"">"
	Else
		tag = "<h3>"
	End If
	GenDetailsHeading = tag & heading & "</h3>" & vbNewLine & "<p class=""function"">" _
		& signature & "</p>" & vbNewLine
End Function

'! Generate detail information from the @detail tag.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @return HTML snippet with the detail information. Empty string if no detail
'!         information was present.
Private Function GenDetailsInfo(tags)
	Dim info : info = ""

	clog.LogDebug "> GenDetailsInfo(" & TypeName(tags) & ")"

	If tags.Exists("@details") Then
		info = MangleBlankLines(tags("@details"), 1)
		info = EncodeHTMLEntities(info)
		info = "<p>" & Replace(info, vbNewLine, "</p>" & vbLf & "<p>") & "</p>"

		' Remove blank lines.
		info = Replace(info, "<p></p>" & vbLf, "")

		' Mark list items as such.
		Dim re : Set re = CompileRegExp("<p>- (.*)</p>", True, True)
		info = re.Replace(info, "<li>$1</li>")
		' Enclose blocks of list items in <ul></ul> tags.
		re.Pattern = "(^|</p>\n)<li>"
		info = re.Replace(info, "$1<ul>" & vbLf & "<li>")
		re.Pattern = "</li>(\n<p|$)"
		info = re.Replace(info, "</li>" & vbLf & "</ul>$1")

		' Add classifications.
		info = Replace(info, "<p>", "<p class=""description"">")
		info = Replace(info, "<ul>", "<ul class=""description"">")
	End If

	GenDetailsInfo = Replace(info, vbLf, vbNewLine) & vbNewLine
End Function

'! Generate parameter information from @param tags.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
'! @return HTML snippet with the parameter information. Empty string if no
'!         parameter information was present.
Private Function GenParameterInfo(tags, lang)
	Dim param
	Dim info : info = ""

	clog.LogDebug "> GenParameterInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"

	If tags.Exists("@param") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("PARAM")) & ":</h4>" & vbNewLine
		For Each param In tags("@param")
			param = Split(param, " ", 2)
			info = info & "<p class=""value""><code>" & EncodeHTMLEntities(param(0)) & "</code>"
			If UBound(param) > 0 Then info = info & " - " & EncodeHTMLEntities(Trim(param(1)))
			info = info & "</p>" & vbNewLine
		Next
	End If

	GenParameterInfo = info
End Function

'! Generate return value information from the @return tag.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
'! @return HTML snippet with the return value information. Empty string if no
'!         return value information was present.
Private Function GenReturnValueInfo(tags, lang)
	GenReturnValueInfo = ""
	clog.LogDebug "> GenReturnValueInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"
	If tags.Exists("@return") Then GenReturnValueInfo = "<h4>" & EncodeHTMLEntities(localize(lang)("RETURN")) _
		& ":</h4>" & vbNewLine & "<p class=""value"">" & EncodeHTMLEntities(tags("@return")) & "</p>" & vbNewLine
End Function

'! Generate information on the errors raised by a method/procedure from @raise
'! tags.
'!
'! @param  tags   Dictionary with the tag/value pairs from the documentation
'!                header.
'! @param  lang   Documentation language. All generated text that is not read
'!                from the source document(s) is created in this language.
'! @return HTML snippet with the error information. Empty string if no error
'!         information was present.
Private Function GenExceptionInfo(tags, lang)
	Dim errType
	Dim info : info = ""

	clog.LogDebug "> GenExceptionInfo(" & TypeName(tags) & ", " & TypeName(lang) & ")"

	If tags.Exists("@raise") Then
		info = "<h4>" & EncodeHTMLEntities(localize(lang)("EXCEPT")) & ":</h4>" & vbNewLine
		For Each errType In tags("@raise")
			info = info & "<p class=""value"">" & EncodeHTMLEntities(errType) & "</p>" & vbNewLine
		Next
	End If

	GenExceptionInfo = info
End Function

'! Write the section for the given global objects (classes, global constants,
'! global variables, global procedures/functions) to the global index.
'!
'! @param  rs       Recordset with the object information.
'! @param  objType  The type of objects in the recordset.
'! @param  lang     Documentation language. All generated text that is not read
'!                  from the source document(s) is created in this language.
'! @return HTML snippet with information about global objects. Empty string if
'!         no information was present.
Private Function GenGlobals(rs, objType, lang)
	Dim source

	GenGlobals = ""
	If Not (rs.BOF And rs.EOF) Then
		' recordset not empty
		GenGlobals = "<h2>" & localize(lang)(objType) & "</h2>" & vbNewLine
		source = localize(lang)("SOURCEFILE")
		rs.MoveFirst
		Do Until rs.EOF
			GenGlobals = GenGlobals & "<p class=""function""><code><span class=""name""><a href=""" & rs("docpath") & """>"
			If objType = "GLOBAL_PROC" Then
				GenGlobals = GenGlobals & Replace(rs("name"), "(", "</a>(")
			Else
				GenGlobals = GenGlobals & rs("name") & "</a>"
			End If
			GenGlobals = GenGlobals & "</span></code></p>" & vbNewLine _
				& "<p class=""description"">" & rs("description") & "</a></p>" & vbNewLine _
				& "<p class=""sourcefile""><strong>" & source & ":</strong> " & rs("srcpath") & "</a></p>" & vbNewLine
			rs.MoveNext
		Loop
	End If
End Function

'! Create a hyperlink from a given reference. The link is created relative to
'! filename.
'!
'! @param  ref      The hyperlink reference.
'! @param  text     The hyperlink text. If this parameter is empty, the value
'!                  of the ref parameter is used instead.
'! @param  filename Name and path of the documentation file that is currently
'!                  being created.
'! @return HTML snippet with the hyperlink to the reference.
Private Function CreateLink(ByVal ref, ByVal text, filename)
	Dim reURL, reText, link, arrSelf, arrRef, i, sameParent, re

	clog.LogDebug "> CreateLink(" & TypeName(ref) & ", " & TypeName(text) & ", " & TypeName(filename) & ")"
	clog.LogDebug "  ref:      " & ref
	clog.LogDebug "  text:     " & text
	clog.LogDebug "  filename: " & filename

	Set reURL = CompileRegExp("<(.*)>", True, True)
	ref = reURL.Replace(ref, "$1")

	If Not IsEmpty(text) Then
		Set reText = CompileRegExp("^\s*\(\s*(.*)\s*\)\s*$", True, True)
		text = reText.Replace(Trim(text), "$1")
	End If

	If IsInternalReference(ref) Then
		' reference is internal
		clog.LogDebug "Internal reference: " & ref

		filename = Replace(filename, "\", "/")
		ref = ResolveReference(ref)

		clog.LogDebug "<<< " & filename
		clog.LogDebug ">>> " & ref

		If IsEmpty(text) Then
			link = ">" & Mid(ref, InStr(ref, "#")+1)
		Else
			link = ">" & text
		End If

		If filename = Split(ref, "#")(0) Then
			' reference is file-local
			clog.LogDebug "File-local reference: " & ref
			ref = "#" & CanonicalizeID(Mid(ref, Len(filename)+2))
		Else
			' reference is documentation-local
			clog.LogDebug "Documentation-local reference: " & ref
			' strip those parent directories from filename and ref that are common
			' to both paths
			arrSelf = Split(fso.GetParentFolderName(filename), "/")
			arrRef = Split(ref, "/")
			i = 0
			sameParent = True
			While i <= Min(UBound(arrSelf), UBound(arrRef)) And sameParent
				' Cannot check this in the While condition, because the lousy piece of
				' junk that is VBScript is too stupid to skip checking the second
				' condition when the first one already evaluated to False (thus raising
				' an "Index Out of Bounds" error when i > UBound(arrXXX)). *grmbl*
				If arrSelf(i) = arrRef(i) Then
					i = i + 1
				Else
					sameParent = False
				End If
			Wend
			On Error Goto 0
			clog.LogDebug "<<< " & Join(Slice(arrSelf, i, UBound(arrSelf)), "/")
			clog.LogDebug ">>> " & Join(Slice(arrRef, i, UBound(arrRef)), "/")
			Set re = CompileRegExp("[^/]+", True, True)
			ref = re.Replace(Join(Slice(arrSelf, i, UBound(arrSelf)), "/"), "..") & "/" & Join(Slice(arrRef, i, UBound(arrRef)), "/")
			i = InStrRev(ref, "#")
			If i > 0 Then ref = Mid(ref, 1, i) & CanonicalizeID(Mid(ref, i+1))
		End If
	Else
		' reference is external
		clog.LogDebug "External reference: " & ref
		If IsEmpty(text) Then
			link = " target=""_blank"">" & ref
		Else
			link = " target=""_blank"">" & text
		End If
	End If

	CreateLink = "<a href=""" & ref & """" & link & "</a>"
End Function

'! Create a mailto link from a given e-mail address.
'!
'! @param  addr   E-mail address.
'! @return HTML snippet with the mailto link.
Private Function CreateMailtoLink(ByVal addr)
	clog.LogDebug "> CreateMailtoLink(" & TypeName(addr) & ")"

	Dim reURL : Set reURL = CompileRegExp("<(.*)>", True, True)
	addr = reURL.Replace(addr , "$1")

	CreateMailtoLink = "<a href=""mailto:" & addr & """>" & addr & "</a>"
End Function

'! Create a stylesheet with the given filename.
'!
'! @param  filename   Name (including relative or absolute path) of the file
'!                    to create.
Private Sub CreateStylesheet(filename)
	clog.LogDebug "Creating stylesheet " & filename & " ..."
	Dim f : Set f = fso.OpenTextFile(filename, ForWriting, True)
	f.WriteLine "* { margin: 0; padding: 0; border: 0; }" & vbNewLine _
		& "body { margin: 10px; margin-bottom: 30px; font-family: " & TextFont & "; font-size: " & BaseFontSize & "; }" & vbNewLine _
		& "h1,h2,h3,h4 { font-weight: bold; }" & vbNewLine _
		& "h1 { font-size: 200%; margin-bottom: 10px; }" & vbNewLine _
		& "h2 { background-color: #ccccff; border: 1px solid black; font-size: 150%; margin: 20px 0 10px; padding: 10px 5px; }" & vbNewLine _
		& "h3,p { margin-bottom: 5px; }" & vbNewLine _
		& "h4,p.description,p.sourcefile { margin: 3px 0 0 50px; }" & vbNewLine _
		& "h4 { margin-top: 6px; margin-bottom: 4px; }" & vbNewLine _
		& "p.value { margin-left: 100px; }" & vbNewLine _
		& "p.footer { margin-top: 20px; text-align: center; font-size: 10px; }" & vbNewLine _
		& "code { font-family: " & CodeFont & "; }" & vbNewLine _
		& "span.name { font-weight: bold; }" & vbNewLine _
		& "hr { border: 1px solid #a0a0a0; width: 94%; margin: 10px 3%; }" & vbNewLine _
		& "ul { list-style: disc inside; margin-left: 50px; padding: 5px 0; }" & vbNewLine _
		& "ul.description { margin-left: 75px; }" & vbNewLine _
		& "li { text-indent: -1em; margin-left: 1em; }" & vbNewLine _
		& ".default { font-style: italic; }" & vbNewLine _
		& ".default:before { content: ""*"" }"
	f.Close
End Sub

' ------------------------------------------------------------------------------
' Consistency checks
' ------------------------------------------------------------------------------

'! Apply some consistency checks to documentation of procedures and functions.
'!
'! @param  name      Name of the procedure or function.
'! @param  params    Array with the parameter names of the procedure or function.
'! @param  tags      A dictionary with the values of the documentation tags.
'! @param  funcType  Type of the procedure or function (function/sub).
Private Sub CheckConsistency(name, params, tags, funcType)
	If Not tags.Exists("@brief") And Not beQuiet Then clog.LogWarning "No description for " & name & "() found."
	If tags.Exists("@param") Then
		CheckParameterMismatch params, tags("@param"), name
	Else
		CheckParameterMismatch params, Array(), name
	End If
	CheckRetvalMismatch funcType, name, tags.Exists("@return")
End Sub

'! Check for mismatches between the documented and the actual parameters of a
'! procedure or function. In case of a mismatch a warning is logged.
'!
'! @param  codeParams  Array with the actual parameters from the code.
'! @param  docParams   Array with the documented parameters.
'! @param  name        Name of the procedure or function.
Private Sub CheckParameterMismatch(ByVal codeParams, ByVal docParams, ByVal name)
	Dim missing, undocumented

	' docParams that are not present in codeParams are missing (not implemented)
	missing = GetMissing(docParams, codeParams)
	' codeParams that are not present in docParams are undocumented
	undocumented = GetMissing(codeParams, docParams)

	If Not beQuiet Then
		If UBound(undocumented) > -1 Then clog.LogWarning "Undocumented parameters in " & name & "(): " & Join(undocumented, ", ")
		If UBound(missing) > -1 Then clog.LogWarning "Parameters not implemented in " & name & "(): " & Join(missing, ", ")
	End If
End Sub

'! Check the consistency of actual and documented parameters of a property. In
'! case of a mismatch a warning is logged.
'!
'! For a readable property, both parameter sets must match. For a writable
'! property there must be one additional codeParam (the value that will be
'! assigned to the property).
'!
'! @param  codeParams  Array with the actual parameters from the code.
'! @param  docParams   Array with the documented parameters.
'! @param  name        Name of the procedure or function.
'! @param  isReadable  Boolean value indicating if the property can be read.
Private Sub CheckPropParamConsistency(codeParams, docParams, name, isReadable)
	Dim missing, undocumented

	' docParams that are not present in codeParams are missing (not implemented)
	missing = GetMissing(docParams, codeParams)
	' codeParams that are not present in docParams are undocumented
	undocumented = GetMissing(codeParams, docParams)

	If Not beQuiet Then
		If Not isReadable Then
			' Setter functions for properties have one parameter (the value that will
			' be assigned to the property) that doesn't require documentation.
			If UBound(undocumented) > 0 Then clog.LogWarning "Undocumented parameter in setter for property " & name & ": " & Join(undocumented, ", ")
			If UBound(missing) > -1 Then clog.LogWarning "Parameter not implemented in setter for property " & name & ": " & Join(missing, ", ")
		Else
			If UBound(undocumented) > -1 Then clog.LogWarning "Undocumented parameter in getter for property " & name & ": " & Join(undocumented, ", ")
			If UBound(missing) > -1 Then clog.LogWarning "Parameter not implemented in getter for property " & name & ": " & Join(missing, ", ")
		End If
	End If
End Sub

'! Return an array with those elements from arr1 that are not present in arr2.
'! Elements of both arrays are assumed to be strings. Comparison between the
'! elements is case-insensitive. Empty parameters are treated as empty arrays.
'!
'! @param  arr1   An array.
'! @param  arr2   Another array.
'! @return Array with elements from arr1 that are missing from arr2.
Private Function GetMissing(arr1, arr2)
	Dim missing, e1, e2, found

	clog.LogDebug "> GetMissing(" & TypeName(arr1) & ", " & TypeName(arr2) & ")"

	missing = Array()

	If IsEmpty(arr1) Then arr1 = Array()
	If IsEmpty(arr2) Then arr2 = Array()

	' arr1 and arr2 may contain lists of parameter names as well as lists of
	' @param tags, which consist not only of the parameter names, but also of
	' the description associated with the name. Splitting the array elements
	' makes sure that only parameter names are used in the comparison.
	For Each e1 In arr1
		e1 = Split(Trim(e1))(0)
		found = False
		For Each e2 In arr2
			e2 = Split(Trim(e2))(0)
			If LCase(e1) = LCase(e2) Then
				found = True
				Exit For
			End If
		Next
		If Not found Then
			ReDim Preserve missing(UBound(missing)+1)
			missing(UBound(missing)) = e1
		End If
	Next

	GetMissing = missing
End Function

'! Check for return value mismatches. Functions must have a return value, subs
'! must not have a return value. In case of a mismatch a warning is logged.
'!
'! @param  funcType    Type of the procedure or function (function/sub).
'! @param  name        Name of the procedure or function.
'! @param  hasRetval   Flag indicating if the procedure or function has a
'!                     documented return value.
Private Sub CheckRetvalMismatch(ByVal funcType, ByVal name, ByVal hasRetval)
	Select Case LCase(funcType)
		Case "function" If Not hasRetval And Not beQuiet Then clog.LogWarning "Undocumented return value for method " & name & "()."
		Case "sub" If hasRetval And Not beQuiet Then clog.LogWarning "Method " & name & "() cannot have a return value."
		Case Else clog.LogError "CheckRetvalMismatch(): Invalid type " & funcType & "."
	End Select
End Sub

'! Check for pointless documentation tags in the doc comments of identifiers.
'! Applies to both variables and constants.
'!
'! @param  name   Name of the identifier.
'! @param  tags   A dictionary with the values of the documentation tags.
Private Sub CheckIdentifierTags(ByVal name, ByVal tags)
	If Not tags.Exists("@brief") And Not beQuiet Then clog.LogWarning "No description for identifier(s) " & Trim(name) & " found."
	If tags.Exists("@param") And Not beQuiet Then clog.LogWarning "Parameter documentation found, but " & name & " is an identifier."
	If tags.Exists("@return") And Not beQuiet Then clog.LogWarning "Return value documentation found, but " & name & " is an identifier."
	If tags.Exists("@raise") And Not beQuiet Then clog.LogWarning "Exception documentation found, but " & name & " is an identifier."
End Sub

'! Check the given string for remaining code. Issue a warning, if there's still
'! code left (i.e. the string does not consist of whitespace only). Should the
'! string contain an "Option Explicit" statement, that statement is ignored.
'!
'! @param  str  The string to check.
Private Sub CheckRemainingCode(str)
	' "Option Explicit" statement can be ignored, so remove it.
	Dim re : Set re = CompileRegExp("Option[ \t]+Explicit", True, True)
	str = re.Replace(str, "")
	' Also remove comment lines.
	re.Pattern = "(^|\n)[ \t]*'.*"
	str = re.Replace(str, vbLf)

	If Trim(Replace(Replace(str, vbTab, ""), vbLf, "")) <> "" Then
		' there's still some (global) code left
		str = MangleBlankLines(Replace(str, vbLf, vbNewLine), 2)
		str = "> " & Replace(str, vbNewLine, vbNewLine & "> ")  ' prepend each line with "> "
		If Not beQuiet Then clog.LogWarning "Unencapsulated global code:" & vbNewLine & str
	End If
End Sub

' ------------------------------------------------------------------------------
' Helper functions
' ------------------------------------------------------------------------------

'! Compile a new regular expression.
'!
'! @param  pattern      The pattern for the regular expression.
'! @param  ignoreCase   Boolean value indicating whether the regular expression
'!                      should be treated case-insensitive or not.
'! @param  searchGlobal Boolean value indicating whether all matches or just
'!                      the first one should be returned.
'! @return The prepared regular expression object.
Private Function CompileRegExp(pattern, ignoreCase, searchGlobal)
	Set CompileRegExp = New RegExp
	CompileRegExp.Pattern = pattern
	CompileRegExp.IgnoreCase = Not Not ignoreCase
	CompileRegExp.Global = Not Not searchGlobal
End Function

'! Recursively create a directory and all non-existent parent directories.
'!
'! @param  dir  The directory to create.
Private Sub CreateDirectory(ByVal dir)
	clog.LogDebug "> CreateDirectory(" & dir & ")"
	dir = fso.GetAbsolutePathName(dir)
	' The recursion terminates once an existing parent folder is found. Which in
	' the worst case is the drive's root folder.
	If Not fso.FolderExists(dir) Then
		CreateDirectory fso.GetParentFolderName(dir)
		' At this point it's certain that the parent folder does exist, so we can
		' carry on and create the subfolder.
		fso.CreateFolder dir
		clog.LogDebug "Directory " & dir & " created."
	End If
End Sub

'! Format the given date with ISO format "yyyy-mm-dd".
'!
'! @param  val  The date to format.
'! @return The formatted date.
Private Function FormatDate(val)
	FormatDate = Year(val) _
		& "-" & Right("0" & Month(val), 2) _
		& "-" & Right("0" & Day(val), 2)
End Function

'! Append the given value to an array or a (string) variable.
'!
'! @param  var   Reference to a variable that the given value should be appended to.
'! @param  val   The value to append.
Private Sub Append(ByRef var, ByVal val)
	Select Case TypeName(var)
		Case "Variant()"
			ReDim Preserve var(UBound(var)+1)
			var(UBound(var)) = val
		Case "Empty"
			var = val
		Case Else
			var = var & " " & val
	End Select
End Sub

'! Return a boolean value indicating whether the classifier is "private". If
'! anything else but the string "private" is given, the function defaults to
'! False. That allows to determine the visibility of variable and constant
'! declarations as well.
'!
'! @param  classifier   The visibility classifier.
'! @return True if visibility is "private", otherwise False.
Private Function CheckIfPrivate(ByVal classifier)
	If LCase(Trim(Replace(classifier, vbTab, " "))) = "private" Then
		CheckIfPrivate = True
	Else
		CheckIfPrivate = False
	End If
End Function

'! Extract the parameter names from a given parameter string.
'!
'! @param  str  The string to extract the parameter names from.
'! @return Array with the parameter names.
Private Function ExtractParameterNames(ByVal str)
	str = Trim(str)
	If Left(str, 1) = "(" And Right(str, 1) = ")" Then
		str = Mid(str, 2, Len(str)-2)  ' remove enclosing parentheses
	End If

	If Len(str) > 0 Then
		str = Replace(str, vbTab, " ")
		str = Replace(str, "ByVal ", "", 1, vbReplaceAll, vbTextCompare)
		str = Replace(str, "ByRef ", "", 1, vbReplaceAll, vbTextCompare)
		str = Replace(str, " ", "")
		ExtractParameterNames = Split(str, ",")
	Else
		ExtractParameterNames = Array()
	End If
End Function

'! Replace special characters (and some particular character sequences) with
'! their respective HTML entity encoding.
'!
'! @param  text  The text to encode.
'! @return The encoded text.
Private Function EncodeHTMLEntities(ByVal text)
	Dim re

	' Ampersand (&) must be encoded first.
	text = Replace(text, "&", "&amp;")

	' replace/encode character sequences with "special" meanings
	text = Replace(text, "<->", "&harr;")
	text = Replace(text, "<-", "&larr;")
	text = Replace(text, "->", "&rarr;")
	text = Replace(text, "<=>", "&hArr;")
	text = Replace(text, "<=", "&lArr;")
	text = Replace(text, "=>", "&rArr;")
	text = Replace(text, "(c)", "�", 1, vbReplaceAll, vbTextCompare)
	text = Replace(text, "(r)", "�", 1, vbReplaceAll, vbTextCompare)
	' treat sequences of 3 or more dots as ellipses
	Set re = CompileRegExp("\.{3,}", True, True)
	text = re.Replace(text, "�")

	' encode all other HTML entities
	text = Replace(text, "�", "&auml;")
	text = Replace(text, "�", "&Auml;")
	text = Replace(text, "�", "&euml;")
	text = Replace(text, "�", "&Euml;")
	text = Replace(text, "�", "&iuml;")
	text = Replace(text, "�", "&Iuml;")
	text = Replace(text, "�", "&ouml;")
	text = Replace(text, "�", "&Ouml;")
	text = Replace(text, "�", "&uuml;")
	text = Replace(text, "�", "&Uuml;")
	text = Replace(text, "�", "&yuml;")
	text = Replace(text, "�", "&Yuml;")
	text = Replace(text, "�", "&uml;")
	text = Replace(text, "�", "&aacute;")
	text = Replace(text, "�", "&Aacute;")
	text = Replace(text, "�", "&eacute;")
	text = Replace(text, "�", "&Eacute;")
	text = Replace(text, "�", "&iacute;")
	text = Replace(text, "�", "&Iacute;")
	text = Replace(text, "�", "&oacute;")
	text = Replace(text, "�", "&Oacute;")
	text = Replace(text, "�", "&uacute;")
	text = Replace(text, "�", "&Uacute;")
	text = Replace(text, "�", "&yacute;")
	text = Replace(text, "�", "&Yacute;")
	text = Replace(text, "�", "&agrave;")
	text = Replace(text, "�", "&Agrave;")
	text = Replace(text, "�", "&egrave;")
	text = Replace(text, "�", "&Egrave;")
	text = Replace(text, "�", "&igrave;")
	text = Replace(text, "�", "&Igrave;")
	text = Replace(text, "�", "&ograve;")
	text = Replace(text, "�", "&Ograve;")
	text = Replace(text, "�", "&ugrave;")
	text = Replace(text, "�", "&Ugrave;")
	text = Replace(text, "�", "&acirc;")
	text = Replace(text, "�", "&Acirc;")
	text = Replace(text, "�", "&ecirc;")
	text = Replace(text, "�", "&Ecirc;")
	text = Replace(text, "�", "&icirc;")
	text = Replace(text, "�", "&Icirc;")
	text = Replace(text, "�", "&ocirc;")
	text = Replace(text, "�", "&Ocirc;")
	text = Replace(text, "�", "&ucirc;")
	text = Replace(text, "�", "&Ucirc;")
	text = Replace(text, "�", "&circ;")
	text = Replace(text, "�", "&atilde;")
	text = Replace(text, "�", "&Atilde;")
	text = Replace(text, "�", "&ntilde;")
	text = Replace(text, "�", "&Ntilde;")
	text = Replace(text, "�", "&otilde;")
	text = Replace(text, "�", "&Otilde;")
	text = Replace(text, "�", "&tilde;")
	text = Replace(text, "�", "&aring;")
	text = Replace(text, "�", "&Aring;")
	text = Replace(text, "�", "&ccedil;")
	text = Replace(text, "�", "&Ccedil;")
	text = Replace(text, "�", "&cedil;")
	text = Replace(text, "�", "&oslash;")
	text = Replace(text, "�", "&Oslash;")
	text = Replace(text, "�", "&szlig;")
	text = Replace(text, "�", "&aelig;")
	text = Replace(text, "�", "&AElig;")
	text = Replace(text, "�", "&oelig;")
	text = Replace(text, "�", "&OElig;")
	text = Replace(text, "�", "&scaron;")
	text = Replace(text, "�", "&Scaron;")
	text = Replace(text, "�", "&micro;")
	' quotation marks
	text = Replace(text, """", "&quot;")
	'text = Replace(text, "'", "&apos;")  ' Don't encode apostrophes, because HTML Help doesn't understand the encoded entity.
	text = Replace(text, "�", "&laquo;")
	text = Replace(text, "�", "&raquo;")
	text = Replace(text, "�", "&lsaquo;")
	text = Replace(text, "�", "&rsaquo;")
	text = Replace(text, "�", "&lsquo;")
	text = Replace(text, "�", "&rsquo;")
	text = Replace(text, "�", "&sbquo;")
	text = Replace(text, "�", "&ldquo;")
	text = Replace(text, "�", "&rdquo;")
	text = Replace(text, "�", "&bdquo;")
	' currency symbols
	text = Replace(text, "�", "&cent;")
	text = Replace(text, "�", "&euro;")
	text = Replace(text, "�", "&pound;")
	text = Replace(text, "�", "&yen;")
	' other special character
	text = Replace(text, ">", "&gt;")
	text = Replace(text, "<", "&lt;")
	text = Replace(text, "�", "&deg;")
	text = Replace(text, "�", "&copy;")
	text = Replace(text, "�", "&reg;")
	text = Replace(text, "�", "&iexcl;")
	text = Replace(text, "�", "&iquest;")
	text = Replace(text, "�", "&middot;")
	text = Replace(text, "�", "&bull;")
	text = Replace(text, "�", "&sect;")
	text = Replace(text, "�", "&ordf;")
	text = Replace(text, "�", "&ordm;")
	text = Replace(text, "�", "&frac14;")
	text = Replace(text, "�", "&frac12;")
	text = Replace(text, "�", "&frac34;")
	text = Replace(text, "�", "&sup1;")
	text = Replace(text, "�", "&sup2;")
	text = Replace(text, "�", "&sup3;")
	text = Replace(text, "�", "&macr;")
	text = Replace(text, "�", "&plusmn;")
	text = Replace(text, "�", "&ndash;")
	text = Replace(text, "�", "&mdash;")
	text = Replace(text, "�", "&hellip;")

	EncodeHTMLEntities = text
End Function

'! Mangle multiple blank lines in the given string into the given number of
'! newlines. Also remove leading and trailing newlines.
'!
'! @param  str    The string to process.
'! @param  number Number of newlines to use as replacement.
'! @return The string without the unwanted newlines.
Private Function MangleBlankLines(ByVal str, ByVal number)
	Dim re, i, replacement

	clog.LogDebug "> MangleBlankLines(" & TypeName(str) & ", " & TypeName(number) & ")"

	Set re = New RegExp
	re.Global = True

	' Remove spaces and tabs from lines consisting only of spaces and/or tabs.
	re.Pattern = "^[ \t]*$"
	str = Split(str, vbNewLine)
	For i = LBound(str) To UBound(str)
		str(i) = re.Replace(str(i), "")
	Next
	str = Join(str, vbNewLine)

	' Mangle multiple newlines. It would've been nice to be able to create the
	' replacement (a string of newlines) like this: String(n, vbNewLine).
	' Unfortunately, String() only works with single characters, while vbNewLine
	' might consist of two characters (CR + LF), depending on the platform.
	' Therefore the workaround to create a string with the desired number of
	' spaces, and then replace the spaces with newlines.
	re.Pattern = "(" & vbNewLine & "){3,}"
	replacement = Replace(Space(number), " ", vbNewLine)
	str = re.Replace(str, replacement)

	' Remove leading/trailing newlines.
	re.Pattern = "(^" & replacement & "|" & replacement & "$)"
	str = re.Replace(str, "")

	MangleBlankLines = str
End Function

'! Extract named anchors from the documentation data structure. The anchor name
'! is either the bare name of the target or the combination filename#name.
'! Anchor names never contain a parameter list, only the anchor targets do.
'!
'! @param  doc  The documentation data.
'! @return A dictionary that maps unique identifiers to the docRoot-relative
'!         path#anchor-name of the documentation item referenced by the
'!         identifier.
Private Function ExtractAnchors(doc)
	Dim anchors, dir, filename, elementType, key, name, name2, parentDir

	clog.LogDebug "> ExtractAnchors(" & TypeName(doc) & ")"

	Set anchors = CreateObject("Scripting.Dictionary")

	For Each dir In doc.Keys
		filename = fso.BuildPath(dir, IndexFileName)
		clog.LogDebug "Extracting anchors of " & filename

		' enumerate non-class targets
		For Each elementType In Array("Procedures", "Constants", "Variables")
			For Each name In doc(dir)(elementType).Keys
				key = name
				key = AddAnchor(anchors, key, filename & "#" & key, filename & "#" & name)
				' for procedures/functions append the arguments to the target
				If elementType = "Procedures" Then anchors(key) = anchors(key) _
					& "(" & Join(doc(dir)("Procedures")(name)("Parameters"), ",") & ")"
			Next
		Next

		' enumerate class and class-member targets
		parentDir = fso.GetParentFolderName(filename)
		For Each name In doc(dir)("Classes").Keys
			filename = fso.BuildPath(parentDir, name & ".html")
			clog.LogDebug "Extracting anchors of " & filename
			key = name
			AddAnchor anchors, key, filename, filename

			' enumerate class-member targets
			For Each elementType In Array("Constructor", "Destructor", "Properties", "Methods", "Fields")
				With doc(dir)("Classes")(name)
					If elementType = "Constructor" And .Item("Constructor").Count > 0 Then
						key = name & "#Class_Initialize"
						AddAnchor anchors, key, fso.BuildPath(parentDir, key), filename & "#Class_Initialize()"
					ElseIf elementType = "Destructor" And .Item("Destructor").Count > 0 Then
						key = name & "#Class_Terminate"
						AddAnchor anchors, key, fso.BuildPath(parentDir, key), filename & "#Class_Terminate()"
					Else
						For Each name2 In .Item(elementType).Keys
							key = name2
							key = AddAnchor(anchors, key, filename & "#" & key, filename & "#" & name2)
							If elementType = "Methods" Then anchors(key) = anchors(key) _
								& "(" & Join(.Item("Methods")(name2)("Parameters"), ",") & ")"
						Next
					End If
				End With
			Next
		Next
	Next

	For Each key In anchors.Keys
		If IsNull(anchors(key)) Then anchors.Remove(key)
	Next

	Set ExtractAnchors = anchors
End Function

'! Add an anchor entry to the given dictionary. If the given key is already
'! present, use altKey instead and remap the value of the existing key. Abort
'! script execution in case of an unresolvable name conflict.
'!
'! @param  dict     A dictionary of anchors.
'! @param  key      The key name to be used for mapping the anchor.
'! @param  altKey   An alternative key name to be used when the primary key
'!                  name is already in use.
'! @param  anchor   The anchor to be added to the dictionary.
'! @return The key name that was used when adding the value to the dictionary.
Private Function AddAnchor(ByRef dict, ByVal key, ByVal altKey, ByVal anchor)
	Dim re, newKey

	clog.LogDebug "> AddAnchor(" & TypeName(dict) & ", " & TypeName(key) & ", " & TypeName(altKey) & ", " & TypeName(anchor) & ")"

	key = LCase(Trim(key))
	altKey = LCase(Trim(altKey))
	anchor = Replace(anchor, "\", "/")

	If Not dict.Exists(key) Then
		clog.LogDebug "Adding key " & key & vbTab & "-> " & anchor
		dict.Add key, anchor
		AddAnchor = key
	Else
		If Not beQuiet Then clog.LogWarning "Potential name conflict: " & key

		altKey = Replace(altKey, ".html", "", 1, vbReplaceAll, vbTextCompare)
		If dict.Exists(altKey) Then
			clog.LogError "Name conflict: " & key & " and " & altKey & " already exist."
			WScript.Quit(1)
		Else
			If Not IsNull(dict(key)) Then
				' Mark key as ambiguous by moving its value to newKey and setting key
				' to Null.
				Set re = CompileRegExp("\(.*\)$", True, True)
				newKey = LCase(re.Replace(Replace(Trim(dict(key)), ".html", "", 1, vbReplaceAll, vbTextCompare), ""))
				If dict.Exists(newKey) Then
					clog.LogError "Cannot remap anchor of key " & key & ". Key " & newKey & " already exists."
					WScript.Quit(1)
				ElseIf newKey = altKey Then
					clog.LogError "Name conflict: existing entry " & key & " would be remapped to alternative key name " & altKey & "."
					WScript.Quit(1)
				Else
					dict.Add newKey, dict(key)
					dict(key) = Null  ' indicator that there already has been a name conflict
				End If
			End If
		End If

		clog.LogDebug "Adding alternative key " & altKey & vbTab & "-> " & anchor
		dict.Add altKey, anchor
		AddAnchor = altKey
	End If
End Function

'! Check if the given reference points towards a documented element.
'!
'! @param  ref  The reference to check.
'! @return True if the reference is internal, otherwise False.
Private Function IsInternalReference(ByVal ref)
	IsInternalReference = Not IsNull(ResolveReference(ref))
End Function

'! Returns the location of the anchor the given reference points to if it
'! exists in the documentation, or Null if no location exists. The function
'! first checks the keys of the anchor list for an exact match. If no exact
'! match is found, the keys are checked for partial matches. If still no match
'! is found, the values are checked for partial matches as well. If any of
'! these steps finds more than one match, the script execution is aborted,
'! because the reference was ambiguous.
'!
'! @param  ref  The reference to check.
'! @return The path to the referenced item or Null if no match was found.
Private Function ResolveReference(ByVal ref)
	Dim key, anchor, matches

	clog.LogDebug "> ResolveReference(" & TypeName(ref) & ")"
	clog.LogDebug "  ref: " & ref

	If Left(ref, 1) = "#" Then ref = Mid(ref, 2)
	' anchors.Keys never contains entries with argument lists
	If InStr(ref, "(") > 0 Then ref = Left(ref, InStr(ref, "(")-1)
	' anchors.Keys contains only lowercase entries
	ref = LCase(ref)

	' first check if the given anchor has an exact match in the anchors.Keys
	If anchors.Exists(ref) Then
		clog.LogDebug "Exact match for " & ref & ": " & anchors(ref)
		ResolveReference = anchors(ref)
	Else ' if no exact match is found: check for partial matches
		matches = Array()
		clog.LogDebug "Checking keys ..."
		' check if the anchors keys contain an entry that ends with ref
		For Each key In anchors.Keys
			If Right(key, Len(ref)) = ref Then
				clog.LogDebug "Found match: " & key
				ReDim Preserve matches(UBound(matches)+1)
				matches(UBound(matches)) = anchors(key)
			End If
		Next

		If UBound(matches) < 0 Then
			' no match found => check values to make sure
			clog.LogDebug "Checking values ..."
			' check if any anchor target contains the (sub)string ref
			For Each anchor In anchors.Items
				If InStr(1, LCase(anchor), ref, vbTextCompare) > 0 Then
					clog.LogDebug "Found match: " & anchor
					ReDim Preserve matches(UBound(matches)+1)
					matches(UBound(matches)) = anchor
				End If
			Next
		End If

		Select Case UBound(matches)
		Case -1   ' no match found
			ResolveReference = Null
		Case 0    ' one match found
			ResolveReference = matches(0)
		Case Else ' two or more matches found => ambiguous reference!
			clog.LogError "Ambiguous reference " & ref & ". Matches found:" & vbNewLine & vbTab & Join(matches, vbNewLine & vbTab)
			WScript.Quit(1)
		End Select
	End If
End Function

'! Return the subject from the HTML file with the given filename. "Subject"
'! here refers to the first heading (text between <h1> and </h1>) in the HTML
'! file. If no match is found, an empty string is returned.
'!
'! @param  filename   The name of the HTML file
'! @return The title from the HTML file.
Private Function GetSubject(filename)
	Dim f, content, re, m

	GetSubject = ""

	Set f = fso.OpenTextFile(filename, ForReading)
	content = f.ReadAll
	f.Close

	Set re = CompileRegExp("<h1>(.*?)</h1>", True, False) ' .Global=False => first match wins
	For Each m In re.Execute(content)
		GetSubject = Trim(m.SubMatches(0))
	Next
End Function

'! Ensure that an anchor's ID conforms to the XHTML specifications. Invalid
'! characters are replaced by underscores.
'!
'! @param  id   The ID to canonicalize.
'! @return The canonicalized ID.
'!
'! @see http://www.w3.org/TR/xhtml1/guidelines.html#C_8
'! @see http://www.w3.org/TR/html4/types.html#h-6.2
Private Function CanonicalizeID(ByVal id)
	Dim re

	' Remove spaces.
	id = Replace(id, " ", "")

	' Avoid trailing underscores from parentheses. This can be done without
	' problem, because an identifier must be unique at file-level anyway.
	If Right(id, 1) = ")" Then id = Mid(id, 1, Len(id)-1)
	If Right(id, 1) = "(" Then id = Mid(id, 1, Len(id)-1)

	' Replace opening parentheses with colons. Replace all other invalid
	' characters (e.g. commas in parameter lists) with dots, because colons
	' and dots aren't valid characters for identifiers, so we won't create
	' any conflicts here (e.g. foo_bar() vs. foo(bar)).
	id = Replace(id, "(", ":")
	Set re = CompileRegExp("[^A-Za-z0-9:_.-]", True, True)
	id = re.Replace(id, ".")

	' No need to verify if the first character is an ASCII letter, because the
	' requirements for VBScript identifiers already enforce this in the source
	' code (i.e. the script won't run otherwise).

	CanonicalizeID = id
End Function

'! Create a disconnected recordset with 4 fields: name, docpath, srcpath and
'! description.
'!
'! @return The newly created recordset.
Private Function CreateRecordset()
	Const adVarChar = 200
	Const maxChars  = 255

	Dim rs : Set rs= CreateObject("ADOR.Recordset")
	rs.Fields.Append "name", adVarChar, maxChars
	rs.Fields.Append "docpath", adVarChar, maxChars
	rs.Fields.Append "srcpath", adVarChar, maxChars
	rs.Fields.Append "description", adVarChar, maxChars
	rs.Open

	Set CreateRecordset = rs
End Function

'! Sort a given array in ascending order. This is merely a wrapper for
'! QuickSort(), so that I can simply call Sort(array) without having to
'! specify the boundaries in the inital function call. This is also to
'! avoid changing the original array.
'!
'! @param  arr  The array to sort.
'! @return The array sorted in ascending order.
'!
'! @see #QuickSort
Private Function Sort(ByVal arr)
	QuickSort arr, 0, UBound(arr)
	Sort = arr
End Function

'! Sort a given array in ascending order, using the quicksort algorithm.
'!
'! @param  arr    The array to sort.
'! @param  left   Left (lower) boundary of the array slice the current
'!                recursion step will operate on.
'! @param  right  Right (upper) boundary of the array slice the current
'!                recursion step will operate on.
'!
'! @see http://en.wikipedia.org/wiki/Quicksort
Private Sub QuickSort(arr, left, right)
	Dim pivot, leftIndex, rightIndex, buffer

	clog.LogDebug "> QuickSort(" & TypeName(arr) & ", " & TypeName(left) & ", " & TypeName(right) & ")"

	leftIndex = left
	rightIndex = right

	If right - left > 0 Then
		pivot = Int((left + right) / 2)

		While leftIndex <= pivot And rightIndex >= pivot
			While arr(leftIndex) < arr(pivot) And leftIndex <= pivot
				leftIndex = leftIndex + 1
			Wend
			While arr(rightIndex) > arr(pivot) And rightIndex >= pivot
				rightIndex = rightIndex - 1
			Wend

			buffer = arr(leftIndex)
			arr(leftIndex) = arr(rightIndex)
			arr(rightIndex) = buffer

			leftIndex = leftIndex + 1
			rightIndex = rightIndex - 1
			If leftIndex - 1 = pivot Then
				rightIndex = rightIndex + 1
				pivot = rightIndex
			ElseIf rightIndex + 1 = pivot Then
				leftIndex = leftIndex - 1
				pivot = leftIndex
			End If
		Wend

		QuickSort arr, left, pivot-1
		QuickSort arr, pivot+1, right
	End If
End Sub

'! Compare two given values and return the smaller one.
'!
'! @param  val1   First value.
'! @param  val2   Second value.
'! @return The minimum of val1 and val2.
Private Function Min(val1, val2)
	If val1 <= val2 Then
		Min = val1
	Else
		Min = val2
	End If
End Function

'! Return a slice (sub-array) from a given array.
'!
'! @param  arr    The source array.
'! @param  first  Index of the beginning of the slice.
'! @param  last   Index of the end of the slice.
'! @return A slice from the given array.
Private Function Slice(arr, first, last)
	Dim a, i

	clog.LogDebug "> Slice(" & TypeName(arr) & ", " & TypeName(first) & ", " & TypeName(last) & ")"

	a = Array()

	' slice cannot contain values from arr if any of these are true:
	' - first > last
	' - both first and last < first index of arr
	' - both first and last > last index of arr
	If first <= last And last >= 0 And first <= UBound(arr) Then
		If first < 0 Then first = 0
		If last > UBound(arr) Then last = UBound(arr)

		Redim a(last-first)

		For i = first To last
			a(i-first) = arr(i)
		Next
	End If

	Slice = a
End Function

'! Display usage information and exit with the given exit code.
'!
'! @param  exitCode   The exit code.
Private Sub PrintUsage(exitCode)
	clog.LogInfo "Usage:" & vbTab & WScript.ScriptName & " [/d] [/a] [/q] [/l:LANG] [/p:NAME] [/e:EXT] [/h:CHM_FILE]" & vbNewLine _
		& vbTab & vbTab & "/i:SOURCE /o:DOC_DIR" & vbNewLine _
		& vbTab & WScript.ScriptName & " /?" & vbNewLine & vbNewLine _
		& vbTab & "/?" & vbTab & "Print this help." & vbNewLine _
		& vbTab & "/a" & vbTab & "Generate documentation for all elements (public" & vbNewLine _
		& vbTab & vbTab & "and private). Without this option, documentation" & vbNewLine _
		& vbTab & vbTab & "is generated for public elements only." & vbNewLine _
		& vbTab & "/d" & vbTab & "Enable debug messages. (you really don't want" & vbNewLine _
		& vbTab & vbTab & "this)" & vbNewLine _
		& vbTab & "/e" & vbTab & "Process files with the given extension." & vbNewLine _
		& vbTab & vbTab & "(default: " & DefaultExtension & ")." & vbNewLine _
		& vbTab & "/h" & vbTab & "Create CHM_FILE in addition to normal HTML" & vbNewLine _
		& vbTab & vbTab & "output. (requires HTML Help Workshop)" & vbNewLine _
		& vbTab & "/i" & vbTab & "Read input files from SOURCE. Can be either a file" & vbNewLine _
		& vbTab & vbTab & "or a directory. (required)" & vbNewLine _
		& vbTab & "/l" & vbTab & "Generate localized output (available: " & Join(Sort(localize.Keys), ",") & ";" & vbNewLine _
		& vbTab & vbTab & "default: " & DefaultLanguage & ")." & vbNewLine _
		& vbTab & "/o" & vbTab & "Create output files in DOC_DIR. (required)" & vbNewLine _
		& vbTab & "/p" & vbTab & "Use NAME as the project name." & vbNewLine _
		& vbTab & "/q" & vbTab & "Don't print warnings. Ignored if debug messages" & vbNewLine _
		& vbTab & vbTab & "are enabled."
	WScript.Quit exitCode
End Sub

' ==============================================================================

'! Class for abstract logging to one or more logging facilities. Valid
'! facilities are:
'!
'! - interactive desktop/console
'! - log file
'! - eventlog
'!
'! Note that this class does not do any error handling at all. Taking care of
'! errors is entirely up to the calling script.
'!
'! @author  Ansgar Wiechers <ansgar.wiechers@planetcobalt.net>
'! @date    2011-03-13
'! @version 2.0
Class CLogger
	Private validLogLevels
	Private logToConsoleEnabled
	Private logToFileEnabled
	Private logFileName
	Private logFileHandle
	Private overwriteFile
	Private sep
	Private logToEventlogEnabled
	Private sh
	Private addTimestamp
	Private debugEnabled
	Private vbsDebug

	'! Enable or disable logging to desktop/console. Depending on whether the
	'! script is run via wscript.exe or cscript.exe, the message is either
	'! displayed as a MsgBox() popup or printed to the console. This facility
	'! is enabled by default when the script is run interactively.
	'!
	'! Console output is printed to StdOut for Info and Debug messages, and to
	'! StdErr for Warning and Error messages.
	Public Property Get LogToConsole
		LogToConsole = logToConsoleEnabled
	End Property

	Public Property Let LogToConsole(ByVal enable)
		logToConsoleEnabled = CBool(enable)
	End Property

	'! Indicates whether logging to a file is enabled or disabled. The log file
	'! facility is disabled by default. To enable it, set the LogFile property
	'! to a non-empty string.
	'!
	'! @see #LogFile
	Public Property Get LogToFile
		LogToFile = logToFileEnabled
	End Property

	'! Enable or disable logging to a file by setting or unsetting the log file
	'! name. Logging to a file ie enabled by setting this property to a non-empty
	'! string, and disabled by setting it to an empty string. If the file doesn't
	'! exist, it will be created automatically. By default this facility is
	'! disabled.
	'!
	'! Note that you MUST set the property Overwrite to False BEFORE setting
	'! this property to prevent an existing file from being overwritten!
	'!
	'! @see #Overwrite
	Public Property Get LogFile
		LogFile = logFileName
	End Property

	Public Property Let LogFile(ByVal filename)
		Dim fso, ioMode

		filename = Trim(Replace(filename, vbTab, " "))
		If filename = "" Then
			' Close a previously opened log file.
			If Not logFileHandle Is Nothing Then
				logFileHandle.Close
				Set logFileHandle = Nothing
			End If
			logToFileEnabled = False
		Else
			Set fso = CreateObject("Scripting.FileSystemObject")
			filename = fso.GetAbsolutePathName(filename)
			If logFileName <> filename Then
				' Close a previously opened log file.
				If Not logFileHandle Is Nothing Then logFileHandle.Close

				If overwriteFile Then
					ioMode = 2  ' open for (over)writing
				Else
					ioMode = 8  ' open for appending
				End If

				' Open log file either as ASCII or Unicode, depending on system settings.
				Set logFileHandle = fso.OpenTextFile(filename, ioMode, -2)

				logToFileEnabled = True
			End If
			Set fso = Nothing
		End If

		logFileName = filename
	End Property

	'! Enable or disable overwriting of log files. If disabled, log messages
	'! will be appended to an already existing log file (this is the default).
	'! The property affects only logging to a file and is ignored by all other
	'! facilities.
	'!
	'! Note that changes to this property will not affect already opened log
	'! files until they are re-opened.
	'!
	'! @see #LogFile
	Public Property Get Overwrite
		Overwrite = overwriteFile
	End Property

	Public Property Let Overwrite(ByVal enable)
		overwriteFile = CBool(enable)
	End Property

	'! Separate the fields of log file entries with the given character. The
	'! default is to use tabulators. This property affects only logging to a
	'! file and is ignored by all other facilities.
	'!
	'! @raise  Separator must be a single character (5)
	'! @see http://msdn.microsoft.com/en-us/library/xe43cc8d (VBScript Run-time Errors)
	Public Property Get Separator
		Separator = sep
	End Property

	Public Property Let Separator(ByVal char)
		If Len(char) <> 1 Then
			Err.Raise 5, WScript.ScriptName, "Separator must be a single character."
		Else
			sep = char
		End If
	End Property

	'! Enable or disable logging to the Eventlog. If enabled, messages are
	'! logged to the Application Eventlog. By default this facility is enabled
	'! when the script is run non-interactively, and disabled when the script
	'! is run interactively.
	'!
	'! Logging messages to this facility produces eventlog entries with source
	'! WSH and one of the following IDs:
	'! - Debug:       ID 0 (SUCCESS)
	'! - Error:       ID 1 (ERROR)
	'! - Warning:     ID 2 (WARNING)
	'! - Information: ID 4 (INFORMATION)
	Public Property Get LogToEventlog
		LogToEventlog = logToEventlogEnabled
	End Property

	Public Property Let LogToEventlog(ByVal enable)
		logToEventlogEnabled = CBool(enable)
		If sh Is Nothing And logToEventlogEnabled Then
			Set sh = CreateObject("WScript.Shell")
		ElseIf Not (sh Is Nothing Or logToEventlogEnabled) Then
			Set sh = Nothing
		End If
	End Property

	'! Enable or disable timestamping of log messages. If enabled, the current
	'! date and time is logged with each log message. The default is to not
	'! include timestamps. This property has no effect on Eventlog logging,
	'! because eventlog entries are always timestamped anyway.
	Public Property Get IncludeTimestamp
		IncludeTimestamp = addTimestamp
	End Property

	Public Property Let IncludeTimestamp(ByVal enable)
		addTimestamp = CBool(enable)
	End Property

	'! Enable or disable debug logging. If enabled, debug messages (i.e.
	'! messages passed to the LogDebug() method) are logged to the enabled
	'! facilities. Otherwise debug messages are silently discarded. This
	'! property is disabled by default.
	Public Property Get Debug
		Debug = debugEnabled
	End Property

	Public Property Let Debug(ByVal enable)
		debugEnabled = CBool(enable)
	End Property

	' - Constructor/Destructor ---------------------------------------------------

	'! @brief Constructor.
	'!
	'! Initialize logger objects with default values, i.e. enable console
	'! logging when a script is run interactively or eventlog logging when
	'! it's run non-interactively, etc.
	Private Sub Class_Initialize()
		logToConsoleEnabled = WScript.Interactive

		logToFileEnabled = False
		logFileName = ""
		Set logFileHandle = Nothing
		overwriteFile = False
		sep = vbTab

		logToEventlogEnabled = Not WScript.Interactive

		Set sh = Nothing

		addTimestamp = False
		debugEnabled = False
		vbsDebug = &h0050

		Set validLogLevels = CreateObject("Scripting.Dictionary")
		validLogLevels.Add vbInformation, True
		validLogLevels.Add vbExclamation, True
		validLogLevels.Add vbCritical, True
		validLogLevels.Add vbsDebug, True
	End Sub

	'! @brief Destructor.
	'!
	'! Clean up when a logger object is destroyed, i.e. close file handles, etc.
	Private Sub Class_Terminate()
		If Not logFileHandle Is Nothing Then
			logFileHandle.Close
			Set logFileHandle = Nothing
			logFileName = ""
		End If

		Set sh = Nothing
	End Sub

	' ----------------------------------------------------------------------------

'! Create an error message with hexadecimal error number from the given Err
'! object's properties. Formatted messages will look like "Foo bar (0xDEAD)".
'!
'! Implemented as a global function due to general lack of class methods in
'! VBScript.
'!
'! @param  e   Err object
'! @return Formatted error message consisting of error description and
'!         hexadecimal error number. Empty string if neither error description
'!         nor error number are available.
Public Function FormatErrorMessage(e)
  Dim re : Set re = New RegExp
  re.Global = True
  re.Pattern = "\s+"
  FormatErrorMessage = Trim(Trim(re.Replace(e.Description, " ")) & " (0x" & Hex(e.Number) & ")")
End Function

	'! An alias for LogInfo(). This method exists for convenience reasons.
	'!
	'! @param  msg   The message to log.
	'!
	'! @see #LogInfo(msg)
	Public Sub Log(msg)
		LogInfo msg
	End Sub

	'! Log message with log level "Information".
	'!
	'! @param  msg   The message to log.
	Public Sub LogInfo(msg)
		LogMessage msg, vbInformation
	End Sub

	'! Log message with log level "Warning".
	'!
	'! @param  msg   The message to log.
	Public Sub LogWarning(msg)
		LogMessage msg, vbExclamation
	End Sub

	'! Log message with log level "Error".
	'!
	'! @param  msg   The message to log.
	Public Sub LogError(msg)
		LogMessage msg, vbCritical
	End Sub

	'! Log message with log level "Debug". These messages are logged only if
	'! debugging is enabled, otherwise the messages are silently discarded.
	'!
	'! @param  msg   The message to log.
	'!
	'! @see #Debug
	Public Sub LogDebug(msg)
		If debugEnabled Then LogMessage msg, vbsDebug
	End Sub

	'! Log the given message with the given log level to all enabled facilities.
	'!
	'! @param  msg       The message to log.
	'! @param  logLevel  Logging level (Information, Warning, Error, Debug) of the message.
	'!
	'! @raise  Undefined log level (51)
	'! @see http://msdn.microsoft.com/en-us/library/xe43cc8d (VBScript Run-time Errors)
	Private Sub LogMessage(msg, logLevel)
		Dim tstamp, prefix

		If Not validLogLevels.Exists(logLevel) Then Err.Raise 51, _
			WScript.ScriptName, "Undefined log level '" & logLevel & "'."

		tstamp = Now
		prefix = ""

		' Log to facilite "Console". If the script is run with cscript.exe, messages
		' are printed to StdOut or StdErr, depending on log level. If the script is
		' run with wscript.exe, messages are displayed as MsgBox() pop-ups.
		If logToConsoleEnabled Then
			If InStr(LCase(WScript.FullName), "cscript") <> 0 Then
				If addTimestamp Then prefix = tstamp & vbTab
				Select Case logLevel
					Case vbInformation: WScript.StdOut.WriteLine prefix & msg
					Case vbExclamation: WScript.StdErr.WriteLine prefix & "Warning: " & msg
					Case vbCritical:    WScript.StdErr.WriteLine prefix & "Error: " & msg
					Case vbsDebug:      WScript.StdOut.WriteLine prefix & "DEBUG: " & msg
				End Select
			Else
				If addTimestamp Then prefix = tstamp & vbNewLine & vbNewLine
				If logLevel = vbsDebug Then
					MsgBox prefix & msg, vbOKOnly Or vbInformation, WScript.ScriptName & " (Debug)"
				Else
					MsgBox prefix & msg, vbOKOnly Or logLevel, WScript.ScriptName
				End If
			End If
		End If

		' Log to facility "Logfile".
		If logToFileEnabled Then
			If addTimestamp Then prefix = tstamp & sep
			Select Case logLevel
				Case vbInformation: logFileHandle.WriteLine prefix & "INFO" & sep & msg
				Case vbExclamation: logFileHandle.WriteLine prefix & "WARN" & sep & msg
				Case vbCritical:    logFileHandle.WriteLine prefix & "ERROR" & sep & msg
				Case vbsDebug:      logFileHandle.WriteLine prefix & "DEBUG" & sep & msg
			End Select
		End If

		' Log to facility "Eventlog".
		' Timestamps are automatically logged with this facility, so addTimestamp
		' can be ignored.
		If logToEventlogEnabled Then
			Select Case logLevel
				Case vbInformation: sh.LogEvent 4, msg
				Case vbExclamation: sh.LogEvent 2, msg
				Case vbCritical:    sh.LogEvent 1, msg
				Case vbsDebug:      sh.LogEvent 0, "DEBUG: " & msg
			End Select
		End If
	End Sub
End Class
