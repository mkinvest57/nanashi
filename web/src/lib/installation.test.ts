import { describe, expect, it } from 'vitest'
import { altStoreInstallURL, detectPhonePlatform, sideStoreInstallURL } from './installation'

describe('phone handoff', () => {
  it.each([
    ['Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)', 'iPhone', 5, 'ios'],
    ['Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)', 'iPad', 5, 'ios'],
    ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Version/18.0 Safari/605.1', 'MacIntel', 5, 'ios'],
    ['Mozilla/5.0 (Linux; Android 16; Pixel 10) Chrome/140.0 Mobile', 'Linux armv8l', 5, 'android'],
    ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Chrome/140.0', 'MacIntel', 0, null],
    ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/140.0', 'Win32', 10, null],
    ['Mozilla/5.0 (X11; Linux x86_64) Chrome/140.0', 'Linux x86_64', 0, null],
  ] as const)('chooses the phone platform without treating every touch screen as an iPad (%s)', (userAgent, platform, maxTouchPoints, expected) => {
    expect(detectPhonePlatform({ userAgent, platform, maxTouchPoints })).toBe(expected)
  })

  it('keeps an unknown browser eligible for the desktop handoff', () => {
    expect(detectPhonePlatform({ userAgent: '' })).toBeNull()
  })
})

describe('direct SideStore install link', () => {
  it('passes the whole published download URL as one encoded argument', () => {
    const download = 'https://github.com/mkinvest57/nanashi/releases/download/v12.1.1/Nanashi%20iPhone.ipa?name=one&signature=a%2Bb'
    const target = new URL(sideStoreInstallURL(download)!)
    expect(target.protocol).toBe('sidestore:')
    expect(target.hostname).toBe('install')
    expect([...target.searchParams.keys()]).toEqual(['url'])
    expect(target.searchParams.get('url')).toBe(download)
  })

  it.each(['', '/Nanashi.ipa', 'javascript:alert(1)', 'http://example.com/Nanashi.ipa', 'https://user:password@example.com/Nanashi.ipa'])('does not make an install action from an invalid or insecure download (%s)', value => {
    expect(sideStoreInstallURL(value)).toBeNull()
  })
})

describe('AltStore Classic installation', () => {
  it('selects Classic instead of PAL and preserves the complete IPA URL', () => {
    const download = 'https://github.com/mkinvest57/nanashi/releases/download/v12.1.1/Nanashi.ipa?download=1&name=a%20b'
    const link = new URL(altStoreInstallURL(download)!)
    expect(link.protocol).toBe('altstore-classic:')
    expect(link.hostname).toBe('install')
    expect([...link.searchParams.keys()]).toEqual(['url'])
    expect(link.searchParams.get('url')).toBe(download)
  })
  it.each(['', 'http://example.com/app.ipa', 'javascript:alert(1)', 'https://user:password@example.com/app.ipa'])('rejects invalid download %s', value => {
    expect(altStoreInstallURL(value)).toBeNull()
  })
})
