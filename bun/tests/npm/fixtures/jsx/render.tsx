// A React component with state and an ID, rendered by the JSX proof (US1-1, US1-2).

import { useId, useState } from "react";
export function Counter({ start }: { start: number }) {
  const [count] = useState(start);
  const id = useId();
  return (
    <label htmlFor={id}>
      Count <output id={id}>{count}</output>
    </label>
  );
}
