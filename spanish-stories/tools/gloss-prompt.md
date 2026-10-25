# Glossing prompt for Biblioteca stories

A prompt for an LLM that turns a plain Spanish story into Biblioteca's
`[spanish|english]` text format, which `tools/story_from_text.py` converts to
a story `.json`.

Fill in the four `{{...}}` slots and paste everything between the two
`=====` lines. Plain text works best: one paragraph per line, a blank line
between paragraphs. Fix any spelling you want changed (*fué* → *fue*) before
glossing; the model is told to copy the Spanish exactly.

`tools/gloss_story.py` does all of this through OpenRouter: it splits the
text into parts of about 1,500 words at paragraph boundaries, glosses them
in parallel, checks each one and asks for fixes, and joins them into one
story. By hand, give the model up to about 1,500 words at a time; for every
part after the first, delete the header section of the output (keep only
the story lines), then join the parts with a blank line between them.

Save the plain Spanish you gave it as `plain.txt` and its answer as
`my-story.txt`, then:

```bash
python tools/check_gloss.py plain.txt my-story.txt   # Spanish changed, added or missing
python tools/story_from_text.py my-story.txt         # writes my-story.json
python tools/validate_stories.py my-story.json
```

Weaker models sometimes change a word (in testing, *loco* became *loro* in a
story about parrots). `check_gloss.py` lists each difference. Fix it by hand,
or send the model: "Your file has these differences from the story: <list>.
Fix only those groups and their English, and give the whole file again."

=====

You are glossing a Spanish story for an English-speaking learner. The learner
reads the story on a tablet. Every word is underlined, and tapping it shows
its English meaning. You decide which words are tapped together and what
English each group shows. Your output is read by a program, so the format
must be exact.

STORY
Title: {{TITLE}}
Author / source: {{AUTHOR}}
Level: {{LEVEL}}      (A1, A2, B1, B2 or C1)

{{STORY}}

END OF STORY

## 1. Output format

Your whole answer is a text file with two parts: a header, then the glossed
story. Write nothing else: no greeting, no explanation, no notes at the end,
no ``` code fences, no markdown.

The header is exactly five lines, then one blank line:

    title: <the Spanish title, exactly as given>
    title_en: <the title in English>
    level: <the level, exactly as given>
    author: <the author / source, exactly as given>
    description: <one English sentence saying what happens in the story, under 20 words>

Then the story. Every Spanish word goes inside a pair of square brackets
with its English after a vertical bar:

    [spanish words|english meaning]

Rules for the story part:

1. Every word of the story, including names and numbers, is inside exactly
   one bracket pair. Nothing with letters or digits may appear outside
   brackets.
2. Punctuation stays outside the brackets, in the same place as in the
   original: `. , ; : ! ? ¿ ¡ « » " — … ( )`. Write `¿` and `¡` directly
   before the bracket: `¿[Dónde|Where] [está|is it]?`. Write the dialogue
   dash `—` outside the bracket too: `—[Hola|Hello] —[dijo|said] [Ana|Ana].`
3. A bracket pair never contains punctuation, so a group never crosses a
   comma, period or any other mark. Exception: an abbreviation keeps its
   period (`Vd.`, `Sr.`, `Dr.`).
4. Copy the Spanish exactly: same spelling, accents, capital letters and
   word order. Do not correct, modernize, shorten or skip anything. Reading
   only the Spanish parts and the punctuation, in order, must give back the
   original story word for word. Watch for words that look like a nearby
   word: if the story says `como un loco`, write `[un loco|a madman]`, not
   `un loro` because the story is about parrots.
5. Every bracket has English after the `|`, never empty. The English must
   not contain `[`, `]` or `|`.
6. One paragraph per line. Put one blank line between paragraphs, where the
   original has a new paragraph. A line like `* * *` stays as its own
   paragraph.
7. Glossing must cover the whole story to its last word. Never stop early
   or write "..." or "(continues)".

## 2. How to group words

A group is what the learner taps. It should be the smallest piece that has a
clear meaning on its own and maps cleanly onto English. Most groups are one to
three words; four is uncommon; five is rare. Roughly: 40% of groups are one
word, 35% two words, 20% three words, 5% four or more.

ALWAYS put these together in one group:

- An article, demonstrative, possessive or number with its noun, and any
  adjective in between:
  `[el perro|the dog]` `[una casita|a little house]` `[su padre|his father]`
  `[todas las plumas|all the feathers]` `[un hermoso paraguas|a beautiful umbrella]`
  Never leave `el`, `la`, `los`, `las`, `un`, `una`, `su`, `mi`, `este` alone.
- A preposition with a short object (three words or fewer), including `al`
  and `del`:
  `[en el agua|in the water]` `[al camarero|to the waiter]` `[del río|of the river]`
  `[con mucho cuidado|very carefully]` `[a casa de|to the house of]`
  Personal "a" before a person or animal joins the noun and is not
  translated: `[a las ranas|the frogs]` `[a su mamá|his mother]`.
  If the object is long (an adjective after the noun, a list, a "de"
  phrase), the preposition and noun still go together and the rest gets its
  own group: `[en la punta|on the tip] [de la cola|of their tails]`.
- An object or reflexive pronoun with its verb: `se`, `me`, `te`, `nos`,
  `lo`, `la`, `los`, `las`, `le`, `les`:
  `[se levantó|she got up]` `[le dijeron|they told her]` `[te juro|I swear to you]`
  `[lo ha aprendido Vd.|did you learn it]` `[se las han comido|they ate them up]`
- `no` with its verb: `[no pudieron|they couldn't]` `[no lo sé|I don't know]`.
- Compound and helper verbs with their main verb, and a verb with the
  preposition it needs:
  `[no he leído|I haven't read]` `[se había comido|had eaten]`
  `[vamos a hacer|we're going to do]` `[empezó a|began to]`
  `[tratando de|trying to]` `[no me atrevía a|I didn't dare]`
- Idioms and fixed expressions, whose words mean something different
  together. These are the most useful groups; look for them hard:
  `[hace mucho tiempo|a long time ago]` `[ya lo creo|of course]`
  `[de veras|really]` `[sobre todo|above all]` `[cada vez que|every time]`
  `[a causa de|because of]` `[como de costumbre|as usual]`
  `[hacía buen tiempo|the weather was fine]` `[me daba miedo|frightened me]`
  `[se morían de envidia|were dying of envy]` `[tiene cinco años|is five years old]`
  `[tener la culpa|to be to blame]` `[lo que|what]` `[por qué|why]`
  `[en cuanto|as soon as]` `[al oír|on hearing]` `[a la orilla|on the bank]`
- Names and compound nouns of several words:
  `[Juan Pérez|Juan Pérez]` `[Romeo y Julieta|Romeo and Juliet]`
  `[escamas de pescado|fish scales]` `[las víboras de coral|the coral snakes]`
  `[vaso de agua|glass of water]`

ALWAYS give these their own one-word group:

- Joining words: `[y|and]` `[o|or]` `[pero|but]` `[porque|because]`
  `[cuando|when]` `[si|if]` `[como|like]` / `[como|since]`, and `que` when it
  means "that", "who" or "which": `[que|that]`, `[que|who]`.
- A verb whose subject or object is a separate noun group:
  `[dijo|said] [el comerciante|the merchant]`
  `[aplaudían|clapped] [con la cola|with their tails]`.
- Adverbs and short words standing on their own: `[entonces|then]`
  `[también|also]` `[ya|already]` `[Sí|Yes]` `[No|No]` `[oh|oh]`.

Adjectives after a noun: join them to the noun when the group stays short
(`[pan tierno|fresh bread]`, `[el oso pequeño|the small bear]`); give them
their own group when the noun group is already three words, or when there
are several adjectives in a row (`[medias|stockings] [coloradas|red],
[blancas|white] [y|and] [negras|black]`).

NEVER:

- make a whole clause or sentence one group. `[el oso se fue al bosque|...]`
  is wrong; write `[el oso|the bear] [se fue|went] [al bosque|to the forest]`.
  A sentence of one to three words that is itself an expression is fine:
  `[No lo sé|I don't know]`.
- split an idiom into words that make no sense alone.
  `[tiene|has] [cinco|five] [años|years]` is wrong.
- split a pronoun from its verb. `[se|himself] [levantó|raised]` is wrong.

## 3. How to write the English

1. Translate the group as it means in this sentence, not its dictionary
   meaning. `[tiene cinco años|is five years old]`, not "has five years".
   `[dieron|threw]` when the snakes "dieron un gran baile" (threw a ball).
2. When the verb has no subject word in Spanish, put the English subject in
   the verb's group: `[Tiene|She has]`, `[Planté|I planted]`,
   `[Corrimos|We ran]`, `[Estoy desesperado|I'm desperate]`. When the subject
   is its own group nearby, leave it out of the verb:
   `[dijo|said] [el abuelo|grandfather]`, `[Calló|Was silent] [el marinero|the sailor]`.
3. Keep the Spanish word order. Each group's English must be right for that
   group; the English of all groups read in a row does not need to be a
   smooth English sentence. `¿[En dónde|Where] [murió|did die] [su padre|your father]?`
   is correct.
4. When a word like `éste`, `aquél` or `ella` refers back to someone, you may
   name them: `[contestó|answered] [éste|the waiter]`.
5. Show diminutives and superlatives: `[farolito|little lantern]`,
   `[hermosísimas|very beautiful]`, `[larguísimas|very long]`.
6. `Vd.` / `Ud.` / `usted` is "you": `[Sabe Vd.|Do you know how to]`.
7. Names are glossed as themselves: `[Gómez|Gómez]`. If a name has a
   meaning that matters, add it once in parentheses: `[Bebé|Bebé ("Baby")]`.
8. Alternatives: only when a group really has two meanings that both fit
   here, separate them with space, slash, space: `[las víboras|the snakes / the vipers]`,
   `[voy|am going / will go]`. At most two. Use this rarely, about one group
   in a hundred. Never use it to avoid choosing.
9. Notes in parentheses: only for a thing the learner can't know, such as old
   money, local animals and plants, places, or an old verb form. About one
   group in two hundred. `[Doce reales|Twelve reales (old coins)]`,
   `[las yararás|the yararás (a kind of pit viper)]`, `[Fuese|Went (= se fue)]`.
   Never leave a Spanish word untranslated in the English: `[mates|gourds]`,
   not `[mates|mates]`. Use the meaning the word has where the story is
   set; in South America `el monte` is usually the jungle or the bush, not a
   mountain. Give a word the same meaning each time it means the same thing.
10. When the Spanish group starts a sentence, start its English with a
    capital letter: `[Iba|Was going]`, `[Habían pasado|Had gone by]`.
    Otherwise use lowercase, except for names and "I".
11. Keep the English short and plain, matching the level. No explanations
    beyond the notes above.

## 4. Example

Input:

    Comía un inglés en una fonda y le sacaron, como era natural, pan tierno.

    —Tráigame pan duro —dijo al camarero.

    —No lo hay, señor —contestó éste.

    —Pues que lo hagan. Yo esperaré.

Output (story part):

    [Comía|Was eating] [un inglés|an Englishman] [en una fonda|at an inn] [y|and] [le sacaron|they brought him], [como era natural|naturally], [pan tierno|fresh bread].

    —[Tráigame|Bring me] [pan duro|stale bread] —[dijo|he said] [al camarero|to the waiter].

    —[No lo hay|There isn't any], [señor|sir] —[contestó|answered] [éste|the waiter].

    —[Pues|Then] [que lo hagan|have them make some]. [Yo esperaré|I'll wait].

Input:

    Cierta vez las víboras dieron un gran baile. Invitaron a las ranas y los sapos, a los flamencos, y a los yacarés y los pescados. Los pescados, como no caminan, no pudieron bailar; pero siendo el baile a la orilla del río, los pescados estaban asomados a la arena, y aplaudían con la cola.

Output (story part):

    [Cierta vez|Once] [las víboras|the snakes / the vipers] [dieron|threw] [un gran baile|a big ball (dance)]. [Invitaron|They invited] [a las ranas|the frogs] [y|and] [los sapos|the toads], [a los flamencos|the flamingos], [y|and] [a los yacarés|the caimans] [y|and] [los pescados|the fish]. [Los pescados|The fish], [como|since] [no caminan|they don't walk], [no pudieron|couldn't] [bailar|dance]; [pero|but] [siendo|as was] [el baile|the ball] [a la orilla|on the bank] [del río|of the river], [los pescados|the fish] [estaban asomados|were peeking out] [a la arena|onto the sand], [y|and] [aplaudían|clapped] [con la cola|with their tails].

Input:

    —Cuando yo era niño... —dijo el abuelo, mientras se acomodaba en la vieja butaca.

    Al oír sus primeras palabras, sabíamos ya que nos iba a contar una historieta.

Output (story part):

    —[Cuando|When] [yo era niño|I was a child]... —[dijo|said] [el abuelo|grandfather], [mientras|as] [se acomodaba|he settled himself] [en la vieja butaca|in the old armchair].

    [Al oír|On hearing] [sus primeras palabras|his first words], [sabíamos ya|we already knew] [que|that] [nos iba a contar|he was going to tell us] [una historieta|a little story].

## 5. Check before you answer

- The answer starts with `title:` and has nothing before the header or
  after the last paragraph.
- No letters or digits outside brackets.
- No punctuation inside brackets (except an abbreviation's period).
- No `el`, `la`, `un`, `una`, `se`, `lo`, `le` or `su` alone in a bracket.
- The Spanish, read in order, is the original story word for word, from its
  first word to its last.
- Every bracket has an English meaning that fits this sentence.

=====
