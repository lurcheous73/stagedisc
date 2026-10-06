// MIT licensed release-mode adapter for HD Cookbook BitStreamIO.
package com.hdcookbook.grin.util;
public final class Debug {
    public static final boolean ASSERT = false;
    public static void assertFail() { throw new AssertionError(); }
    public static void assertFail(String message) { throw new AssertionError(message); }
}
