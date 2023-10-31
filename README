# CLI EASY DIFFUSION

A simple command line client for the wonderful [easy-diffusion](https://easydiffusion.github.io/)

## Install

- have ruby and bundler installed
- `git clone` this repo
- `cd` into the cloned directory
- `bundle` (or `rvmsudo bundle`, or `sudo bundle` depending on your setup)

## Usage - prerequisite

- install easy-diffusion
- launch the easy-diffusion server in a terminal window

## An example is worth all words

- in a second terminal
- `cp settings/sample.json settings/spacecrafts.json`
- you can edit spacecrafts.json if you want (eg. change the model)
- `cp prompts/sample.json prompts/spacecrafts.json`
- edit this file and change de prompts to

```JSON
[
  {
    "how_many": 2,
    "positive": "intergalactic spacecraft",
    "negative": "",
    "out_dir": "spacecrafts"
  }
]
```

`ruby cli.rb --settings spacecrafts --prompts spacecrafts`

- you'll get two images generated in images/spacecrafts
- now you want to rerender all these images with different settings, eg. width and height
- create a spacecrafts.json in settings
- edit this file and change width and height values

```JSON
{
  "width": 512,
  "height": 512
}
```

`ruby cli.rb --rerender spacecrafts`

- two new images will be generated in images/spacecrafts-timestamp (timestamp will be current timestamp)

## Notes

- A prompt file can have multiple prompts, each one with a different output directory
- If a prompts/common.json file exists the positive and negative keys will be used (merged) for each image generation
- passing `--howmany N` where N is an integer you can force the number of images generated regardless of the settings "how_many" key value.
- If you want to know more about settings, in the browser used for easy-diffusion open the developer tools, change whatever you want then click "Make image" and in the Network tab have a look at the first request which should be "render" with POST verb.
- you can use --rerender all in which case you need a all.json file in settings, ALL the images will be rerendered using these settings

Have fun !