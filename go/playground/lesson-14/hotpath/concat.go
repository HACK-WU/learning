// Package hotpath contains small functions whose costs are easy to measure.
package hotpath

import "strings"

// ConcatNaive joins parts with repeated string concatenation.
func ConcatNaive(parts []string) string {
	var result string
	for _, part := range parts {
		result += part
	}
	return result
}

// ConcatBuilder joins parts with a pre-sized strings.Builder.
func ConcatBuilder(parts []string) string {
	var builder strings.Builder
	total := 0
	for _, part := range parts {
		total += len(part)
	}
	builder.Grow(total)
	for _, part := range parts {
		builder.WriteString(part)
	}
	return builder.String()
}
