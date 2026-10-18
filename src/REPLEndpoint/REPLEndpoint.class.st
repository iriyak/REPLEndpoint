"
Receives the payload sent as POST in `/repl` and returns, as string, the answer of having evaluated it as a snippet.

If evaluating the snippet signals an Error, Halt or Warning, the answer is an HTTP 500 response with a JSON body. For example, for the snippet `1 / 0`:

{
  ""status-code"": 500,
  ""status-message"": ""Internal Server Error"",
  ""message"": {
    ""kind"": ""runtime"",
    ""class"": ""ZeroDivide"",
    ""messageText"": ""ZeroDivide"",
    ""description"": ""ZeroDivide"",
    ""stack"": [ ""SmallInteger>>/"", ""UndefinedObject>>DoIt"" ]
  },
  ""method"": ""POST"",
  ""uri"": ""/repl""
}

and for the snippet `(3 + ) printString`, which does not compile:

{
  ""status-code"": 500,
  ""status-message"": ""Internal Server Error"",
  ""message"": {
    ""kind"": ""syntax"",
    ""class"": ""CodeError"",
    ""messageText"": ""Variable or expression expected"",
    ""description"": ""CodeError:RBSyntaxErrorNotice UndefinedObject>>#DoIt 6:Variable or expression expected->"",
    ""stack"": [ ]
  },
  ""method"": ""POST"",
  ""uri"": ""/repl""
}

The fields of `message`:
- kind: 'syntax' for a CodeError (the snippet does not compile), otherwise 'runtime'.
- class: the class name of the exception.
- messageText: the exception's message text; its description when it has none (as with ZeroDivide).
- description: the exception's `asString`.
- stack: one line per frame of the snippet itself, from the signal point down to its DoIt. It is empty for syntax errors. Runs of identical lines are collapsed to 'line (xN)' and at most 30 lines are kept.
"
Class {
	#name : 'REPLEndpoint',
	#superclass : 'ZnJSONRestCall',
	#category : 'REPLEndpoint',
	#package : 'REPLEndpoint'
}

{ #category : 'accessing' }
REPLEndpoint class >> pattern [
	^ #('repl')
]

{ #category : 'error handling' }
REPLEndpoint >> errorFrom: anException [
	"Set the response to an HTTP 500 JSON error describing anException."
	| text |
	text := (anException messageText ifNil: [ '' ])
		ifEmpty: [ anException description ].
	self response: (self delegate
		errorResponse: request
		code: 500
		message: (Dictionary new
			at: 'kind' put: ((anException isKindOf: CodeError)
				ifTrue: [ 'syntax' ]
				ifFalse: [ 'runtime' ]);
			at: 'class' put: anException class name asString;
			at: 'messageText' put: text;
			at: 'description' put: anException asString;
			at: 'stack' put: (self stackLinesFor: anException);
			yourself))
]

{ #category : 'public' }
REPLEndpoint >> get [
	^ self
		jsonResponse: 'REPL uses POST to evaluate Smalltalk snippets in this Pharo image'
]

{ #category : 'error handling' }
REPLEndpoint >> lineForContext: aContext [
	"A one-line description of aContext. A block is shown as '[] in <home>' so that its source is not included."
	| line |
	line := [ aContext isBlockContext
			ifTrue: [ '[] in ', aContext home printString ]
			ifFalse: [ aContext printString ] ]
		on: Error
		do: [ :e | '<unprintable frame>' ].
	^ line size > 120
		ifTrue: [ (line first: 119), '...' ]
		ifFalse: [ line ]
]

{ #category : 'public' }
REPLEndpoint >> post [
	| snippet |
	snippet := request entity string.
	^ [ self jsonResponse: (OpalCompiler new evaluate: snippet) asString ]
		on: Error, Halt, Warning
		do: [ :e | self errorFrom: e ]
]

{ #category : 'error handling' }
REPLEndpoint >> stackLinesFor: anException [
	"One line per frame of the snippet itself, from the signal point down to its DoIt.
	Syntax errors have no snippet frames: answer an empty array.
	Runs of identical lines are collapsed to 'line (xN)'; at most 30 lines are kept."
	| all doIt frames lines counts |
	(anException isKindOf: CodeError) ifTrue: [ ^ #() ].
	all := anException signalerContext stack.
	doIt := all findFirst: [ :each | each isBlockContext not and: [ each selector == #DoIt ] ].
	frames := doIt > 0
		ifTrue: [ all first: doIt ]
		ifFalse: [ all first: (all size min: 15) ].
	lines := OrderedCollection new.
	counts := OrderedCollection new.
	frames do: [ :each | | line |
		line := self lineForContext: each.
		(lines notEmpty and: [ lines last = line ])
			ifTrue: [ counts at: counts size put: counts last + 1 ]
			ifFalse: [ lines add: line. counts add: 1 ] ].
	lines := lines withIndexCollect: [ :line :i |
		(counts at: i) > 1
			ifTrue: [ line, ' (x', (counts at: i) printString, ')' ]
			ifFalse: [ line ] ].
	^ lines size > 30
		ifTrue: [ (lines first: 30) asArray copyWith: '... (', (lines size - 30) printString, ' more lines)' ]
		ifFalse: [ lines asArray ]
]
