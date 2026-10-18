"
Receives the payload sent as POST in `/repl` and returns, as string, the answer of having evaluated it as a snippet.
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
