Positions: just after a space, and two letters into a word. Shown: passed the gate and the 3-key minimum.
Right: first word exactly the next word. Saved: keys a Tab user doesn't press, Tab one key taking one word.

| Model | Group | Positions | Shown | Right when shown | Right and shown, of positions | Saved |
|---|---|---|---|---|---|---|
| Qwen3.5-0.8B-Q4_K_M | quotes | 793 | 20.4% | 82.7% | 16.9% | 23.0% |
| Qwen3.5-0.8B-Q4_K_M | idioms | 501 | 20.6% | 91.3% | 18.8% | 25.3% |
| Qwen3.5-0.8B-Q4_K_M | stock | 555 | 21.3% | 83.9% | 17.8% | 30.1% |
| Qwen3.5-0.8B-Q4_K_M | articles | 1205 | 40.6% | 90.2% | 36.6% | 43.6% |
| Qwen3.5-0.8B-Q4_K_M | all | 3054 | 28.6% | 88.1% | 25.1% | 32.9% |
| Qwen3.5-2B-Q4_K_M | quotes | 793 | 33.3% | 88.6% | 29.5% | 39.5% |
| Qwen3.5-2B-Q4_K_M | idioms | 501 | 30.3% | 94.7% | 28.7% | 34.8% |
| Qwen3.5-2B-Q4_K_M | stock | 555 | 25.8% | 86.0% | 22.2% | 37.3% |
| Qwen3.5-2B-Q4_K_M | articles | 1205 | 46.0% | 92.1% | 42.3% | 50.0% |
| Qwen3.5-2B-Q4_K_M | all | 3054 | 36.4% | 90.8% | 33.1% | 42.6% |
| gemma-4-E2B.Q4_K_M | quotes | 793 | 42.9% | 96.8% | 41.5% | 51.9% |
| gemma-4-E2B.Q4_K_M | idioms | 501 | 40.7% | 94.6% | 38.5% | 46.1% |
| gemma-4-E2B.Q4_K_M | stock | 555 | 26.5% | 91.2% | 24.1% | 38.1% |
| gemma-4-E2B.Q4_K_M | articles | 1205 | 47.2% | 93.3% | 44.1% | 52.2% |
| gemma-4-E2B.Q4_K_M | all | 3054 | 41.3% | 94.2% | 38.9% | 48.6% |
| kanana-1.5-2.1b-base.Q4_K_M | quotes | 793 | 40.9% | 96.3% | 39.3% | 49.4% |
| kanana-1.5-2.1b-base.Q4_K_M | idioms | 501 | 36.5% | 96.2% | 35.1% | 43.0% |
| kanana-1.5-2.1b-base.Q4_K_M | stock | 555 | 22.0% | 93.4% | 20.5% | 34.1% |
| kanana-1.5-2.1b-base.Q4_K_M | articles | 1205 | 46.8% | 91.7% | 42.9% | 51.1% |
| kanana-1.5-2.1b-base.Q4_K_M | all | 3054 | 39.1% | 93.8% | 36.6% | 46.3% |

## Examples (prefix -> what each model shows; `-` nothing shown; * right)

**quotes**

- `Veni, ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `vidi,`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Now is ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `the`*; gemma-4-E2B.Q4_K_M: `the time`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Ask not ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `what your`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Double, ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `double,`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Mirror, ` -> Qwen3.5-0.8B-Q4_K_M: `Mirror,`; Qwen3.5-2B-Q4_K_M: `Mirror,`; gemma-4-E2B.Q4_K_M: `mirror on the wall,`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `To be, or ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `not to be?`*; gemma-4-E2B.Q4_K_M: `not to be,`*; kanana-1.5-2.1b-base.Q4_K_M: `not to be,`*

**idioms**

- `Kill two ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `birds with one stone.`*; gemma-4-E2B.Q4_K_M: `birds with one stone:`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Two heads ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `are better than one,`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `A bird in ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `the hand`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Birds of a ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `feather`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Easy come, ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `easy go.`*; gemma-4-E2B.Q4_K_M: `easy go.`*; kanana-1.5-2.1b-base.Q4_K_M: `easy go.`*
- `Every cloud ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `has a silver lining,`*; kanana-1.5-2.1b-base.Q4_K_M: -

**stock**

- `We ` -> Qwen3.5-0.8B-Q4_K_M: `are currently`*; Qwen3.5-2B-Q4_K_M: `are currently finishing the`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: -
- `Thank ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `you for`*; gemma-4-E2B.Q4_K_M: `you for`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Could ` -> Qwen3.5-0.8B-Q4_K_M: `you`*; Qwen3.5-2B-Q4_K_M: `you`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: -
- `Merry ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `Christmas!`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `Thank you ` -> Qwen3.5-0.8B-Q4_K_M: `for`*; Qwen3.5-2B-Q4_K_M: `for`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: -
- `Sorry for ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `the`*; gemma-4-E2B.Q4_K_M: `the`*; kanana-1.5-2.1b-base.Q4_K_M: -

**articles**

- `Climate ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: `change`*; kanana-1.5-2.1b-base.Q4_K_M: -
- `The Cold ` -> Qwen3.5-0.8B-Q4_K_M: `War`*; Qwen3.5-2B-Q4_K_M: `War`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: `War`*
- `Leonardo da ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: -; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: `Vinci,`*
- `The Industrial ` -> Qwen3.5-0.8B-Q4_K_M: `Revolution`*; Qwen3.5-2B-Q4_K_M: `Revolution`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: `Revolution`*
- `Bees are winged ` -> Qwen3.5-0.8B-Q4_K_M: -; Qwen3.5-2B-Q4_K_M: `insects`*; gemma-4-E2B.Q4_K_M: `insects that`*; kanana-1.5-2.1b-base.Q4_K_M: `insects`*
- `A black hole is a ` -> Qwen3.5-0.8B-Q4_K_M: `region of`*; Qwen3.5-2B-Q4_K_M: `region`*; gemma-4-E2B.Q4_K_M: -; kanana-1.5-2.1b-base.Q4_K_M: `region of`*

