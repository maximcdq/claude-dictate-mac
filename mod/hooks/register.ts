import type { Register } from 'claude-code'

const POLL_MS = 100

// Runs in the hidden Claude Code session that ClaudeDictate.app starts with DICTATE_STATE_DIR set: the prompt draft,
// where /voice puts its transcript, is mirrored to live.txt for the app; the app writes "clear" to control.txt once
// it has typed the final text. A prompt is never sent to the model, so dictation spends no tokens.
export const register: Register = on => {
  let seen = ''

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    const dir = await $.env.get('DICTATE_STATE_DIR')
    if (!dir) return result
    const liveFile = `${dir}/live.txt`
    const controlFile = `${dir}/control.txt`
    await $.fs.write(liveFile, '')
    await $.fs.write(controlFile, '')

    $.clock.every(POLL_MS, async () => {
      if ((await $.fs.read(controlFile)) === 'clear') {
        await $.fs.write(controlFile, '')
        await $.prompt.fill({ text: '', mode: 'replace' })
      }
      const { text } = await $.prompt.read()
      if (text === seen) return
      seen = text
      await $.fs.write(liveFile, text)
    })

    return result
  })

  on('prompt.submit', async () => ({ drop: 'ClaudeDictate: dictation only, nothing is sent' }))
}
